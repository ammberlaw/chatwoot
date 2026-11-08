# 单据推着商机走：发了报价单 / 寄了样 / 做了 PI / 转成销售订单，商机阶段自动跟上。
#
# 为什么要这个：商机那五个阶段原本全靠人手工拖，结果没人拖——生产 185 个商机里
# 「下一步」「竞争对手」「丢单原因」各 0 条填写，80 个赢单里 37 个是建立当天就 WON 的
# （也就是成交之后补录的影子）。而同期 610 张销售订单里 607 张有 PI 号。
# 真实业务流一直在跑，只是没人同步去更新另一个地方的状态。
#
# 所以不再要求人去填，改成从单据推。业务员该做的事一件没多。
#
# 两条硬规矩：
#   · **只向前不回退**——已成交的商机不会因为又开了一张 PI 草稿退回「待付款」。
#   · **不覆盖人工判的输单**——LOST 是人看着数据下的结论，单据动作不该把它抹掉。
class Crm::OpportunityStageSync
  # 阶段推进的先后。样品中（SAMPLING）由寄样记录推（见 from_sample）；
  # 它在序里占一格，已经在样品阶段的商机不会被一张报价单拉回「需求确认」。
  STAGE_ORDER = %w[NEEDS_CONFIRMED SAMPLING PENDING_PAYMENT WON].freeze

  KIND_LABEL = { quote: '报价单', pi: 'PI', order: '销售订单', sample: '寄样' }.freeze

  # 报价单只在**发出去之后**才算报价；草稿不算（人还在改，客户没看到）。
  def self.from_quote(quote)
    return nil unless quote&.status == 'SENT'

    new(record: quote, kind: :quote, stage: 'NEEDS_CONFIRMED').call
  end

  # PI 一建出来就算在谈（草稿也算：PI 都开始拟了，这单是真的）；已付款直接推到成交。
  # 单据类型固定是 PI——留痕上要写「由 PI 触发」，不能因为推到了成交就说成是销售订单。
  def self.from_pi(pi_record)
    return nil if pi_record.nil?

    new(record: pi_record, kind: :pi,
        stage: pi_record.status == 'PAID' ? 'WON' : 'PENDING_PAYMENT').call
  end

  # 寄样：推到「样品中」。五个阶段里只有它一直没有单据可依，寄样记录补上了这一环。
  # 只认真的寄出去了的——还没寄、已取消的不推（东西没出门，谈不上在打样）。
  SAMPLE_STAGE_STATUSES = %w[SENT DELIVERED FEEDBACK].freeze

  def self.from_sample(sample)
    return nil unless sample && SAMPLE_STAGE_STATUSES.include?(sample.status)

    new(record: sample, kind: :sample, stage: 'SAMPLING').call
  end

  # 销售订单：到这一步钱已经收了（PI 转单口径），直接成交。
  def self.from_order(order)
    return nil if order.nil?

    new(record: order, kind: :order, stage: 'WON').call
  end

  # kind 决定留痕文案和取哪个单号；stage 决定推到哪一阶段。两者刻意分开——
  # 同一种单据（PI）在不同状态下推到不同阶段，但它始终是一张 PI。
  def initialize(record:, kind:, stage:)
    @record = record
    @kind = kind
    @stage = stage
    @account = record.account
  end

  # 返回被推进的商机；推不动（没客户、或阶段已经更靠后）时返回已找到的商机或 nil。
  def call
    return nil if @record.crm_customer_id.blank?

    opportunity = resolve_opportunity
    return nil if opportunity.nil?

    link_back(opportunity)
    advance(opportunity)
    opportunity
  rescue StandardError => e
    # 同步失败绝不能连累单据本身：报价单/PI 已经存好了，这里只是没跟上状态。
    Rails.logger.error("[OppStageSync] #{@kind}=#{@record.id}: #{e.class} #{e.message}")
    nil
  end

  private

  # 找商机：单据上挂了的 → 这个客户进行中的 → 够大的单自动建一个。
  def resolve_opportunity
    existing = @record.crm_opportunity_id && @account.crm_opportunities.find_by(id: @record.crm_opportunity_id)
    existing || open_one_for_customer || auto_create
  end

  # 没有现成商机时只有**大单**才自动建（2026-11-06 用户定的口径）。
  #
  # 为什么要有门槛：生产 PI 金额中位数只有 458 美金、最小 24 美金，绝大多数是样品单
  # 和小批量试单，每张都立个商机只会把商机列表淹掉。按 1 万美金这条线切，
  # 近四个月每月只有 2~12 张单够格（平均 7 张），进来的都是真该跟的单。
  #
  # 只认报价单和 PI：销售订单走到这一步要么是 PI 转来的（商机在 PI 那步就挂好了），
  # 要么是手工补录的历史单，替它建一个一出生就「已成交」的商机没有意义。
  AUTO_CREATE_KINDS = %i[quote pi].freeze
  # 门槛金额（美金）。换算走中行牌价（Crm::FxRate），不硬编汇率。
  AUTO_CREATE_USD = 10_000

  def auto_create
    return nil unless AUTO_CREATE_KINDS.include?(@kind)
    return nil unless big_enough?

    customer = @account.crm_customers.find_by(id: @record.crm_customer_id)
    return nil if customer.nil?

    created = @account.crm_opportunities.create!(
      crm_customer_id: customer.id,
      owner_id: @record.owner_id || customer.account_owner_id,
      name: "#{customer.name.to_s.truncate(30)}｜#{KIND_LABEL[@kind]} #{doc_no}".strip,
      sales_stage: STAGE_ORDER.first,
      amount_micros: amount, currency: currency,
      last_activity_at: Time.current
    )
    # 建这件事本身也要留痕：不记的话业务员只看到商机列表里凭空多了一条，
    # 不知道是谁、因为什么建的。
    write_note(created, '商机自动创建', "达到自动建单门槛（#{AUTO_CREATE_USD} 美金等值）")
    created
  end

  # 单据金额折人民币后 ≥ 门槛折人民币。两边都用**单据当日**的牌价折，
  # 汇率波动时门槛跟着动，口径不会跟财务那边的折算打架。
  # 牌价查不到（没有这个币种的历史）就不建——宁可不建，不拿 1:1 当汇率蒙。
  def big_enough?
    return false if amount.blank? || amount.to_i <= 0

    doc_cny = to_cny(amount, currency)
    limit_cny = to_cny(AUTO_CREATE_USD * 1_000_000, 'USD')
    doc_cny.present? && limit_cny.present? && doc_cny >= limit_cny
  end

  def to_cny(micros, cur)
    on = doc_date
    rate = Crm::FxRate.rate_for(cur, on) || Crm::FxRate.rate_on_or_after(cur, on)
    rate && (micros.to_i * rate)
  end

  # 折算基准日取单据日期（和销售订单锁汇率同口径，见 Crm::SalesOrder#lock_exchange_rate）。
  def doc_date
    (@record.try(:pi_date) || @record.try(:quote_date) || @record.try(:order_date) ||
      @record.created_at)&.to_date || Time.zone.today
  end

  # 进行中的商机取最近动过的那个。同一个客户同时谈几单时，新单据算在最近在谈的那一单上；
  # 要分开算，人工在商机上改挂即可（单据上的 crm_opportunity_id 一旦有值就以它为准）。
  def open_one_for_customer
    @account.crm_opportunities
            .where(crm_customer_id: @record.crm_customer_id, is_in_public_pool: false)
            .open_stages
            .order(Arel.sql('COALESCE(last_activity_at, updated_at) DESC'))
            .first
  end

  # 单据反挂商机：下次这张单再动（PI 草稿改成已付款）时直接认得出是哪一个，
  # 不用再按客户猜；商机详情页也据此摆出关联单据。
  def link_back(opportunity)
    return if @record.crm_opportunity_id == opportunity.id

    @record.update_columns(crm_opportunity_id: opportunity.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def advance(opportunity)
    target = @stage
    return if opportunity.sales_stage == 'LOST'
    return if rank(opportunity.sales_stage) >= rank(target)

    was = opportunity.sales_stage
    opportunity.update!(sales_stage: target, last_activity_at: Time.current, **money_attrs(opportunity))
    log_note(opportunity, was, target)
  end

  # 金额以最新单据为准——商机金额本来就该是「现在谈的是多少钱」，
  # 而 PI 上的数比人凭印象填的准。单据没金额时不动原值。
  def money_attrs(opportunity)
    return {} if amount.blank? || amount.to_i.zero?
    return {} if opportunity.amount_micros == amount

    { amount_micros: amount, currency: currency.presence || opportunity.currency }
  end

  STAGE_LABEL = { 'NEEDS_CONFIRMED' => '需求确认', 'SAMPLING' => '样品中',
                  'PENDING_PAYMENT' => '待付款', 'WON' => '已成交', 'LOST' => '输单' }.freeze

  # 留痕走跟进记录（商机详情页本来就在读它），不写进 opportunity_remark——
  # 那是业务员自己的备注栏，系统不该往里面塞东西。
  def log_note(opportunity, was, target)
    write_note(opportunity, "阶段自动推进：#{STAGE_LABEL[was]} → #{STAGE_LABEL[target]}")
  end

  def write_note(opportunity, title, extra = nil)
    body = ["触发单据：#{KIND_LABEL[@kind]} #{doc_no}", extra].compact.join('。')
    @account.crm_follow_up_notes.create!(
      crm_customer_id: opportunity.crm_customer_id,
      crm_opportunity_id: opportunity.id,
      owner_id: opportunity.owner_id,
      source: 'SYSTEM', title: title, body: body
    )
  rescue StandardError => e
    # 留痕失败不该让阶段推进/建单回滚——状态已经对了，少一条记录而已。
    Rails.logger.warn("[OppStageSync] 留痕失败 opportunity=#{opportunity.id}: #{e.class} #{e.message}")
  end

  def rank(stage) = STAGE_ORDER.index(stage) || -1

  # 留痕上写哪个号：单据有自己的号，寄样没有号、就写快递单号（那才是能查的东西）。
  def doc_no
    %i[quote_no pi_no order_no tracking_no].filter_map { |m| @record.try(m).presence }.first.to_s
  end

  # 三张单的金额/币种列名各不相同（报价单 total_amount_micros + quote_currency，
  # PI total_amount_micros + currency，销售订单 order_amount_micros + order_currency）。
  def amount = @record.try(:total_amount_micros) || @record.try(:order_amount_micros)

  def currency
    (@record.try(:currency) || @record.try(:quote_currency) || @record.try(:order_currency)).presence
  end
end
