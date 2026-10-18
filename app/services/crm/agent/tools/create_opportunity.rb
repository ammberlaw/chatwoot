# 建一个在谈商机。
#
# 客户表露意向之后该建商机——漏斗、团队看板、预估金额全靠它。
# 以前 agent 只能说「建议你去建个商机」，人九成不会专门回去点那一下。
#
# 商机不是草稿态单据（没有 DRAFT），所以建完明确告诉用户建了什么、在哪看，
# 建错了随手能删。
class Crm::Agent::Tools::CreateOpportunity < Crm::Agent::Tools::Base
  description '为某个客户建一个在谈商机（客户表露意向、开始谈具体项目时用）。建完它会进漏斗和团队看板。'
  param :customer_id, type: 'integer', desc: '客户ID'
  param :name, desc: '商机名称，例如「德国教育局 1200 台教育平板」'
  param :amount, desc: '预估金额（数字，不要带币种符号）', required: false
  param :currency, desc: '币种 USD / EUR / CNY；不传按客户档案的常用币种', required: false
  param :stage, desc: '阶段：NEEDS_CONFIRMED 需求确认（默认）｜SAMPLING 样品中｜PENDING_PAYMENT 待付款', required: false
  param :expected_close_on, desc: '预计成交日期，写成 2026-12-20', required: false
  param :current_need, desc: '客户当前需求：型号、数量、要求', required: false
  param :next_action, desc: '下一步要做什么', required: false

  OPEN_STAGES = %w[NEEDS_CONFIRMED SAMPLING PENDING_PAYMENT].freeze

  # 必填两个显式写出来（RubyLLM 会替我们校验缺参），其余六个塞 opts：
  # 全列出来会撞 rubocop 的参数个数上限。
  def execute(customer_id:, name:, **opts)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户，没法建商机。" if customer.nil?
    return '商机名称不能为空。' if name.to_s.strip.blank?

    opp = create(customer, name, opts)
    scope.record_artifact(kind: 'opportunity', id: opp.id, customer_id: customer.id,
                          label: "商机：#{opp.name.truncate(20)}")
    done_text(customer, opp)
  end

  private

  def create(customer, name, opts)
    scope.account.crm_opportunities.create!(
      belongs_attrs(customer).merge(
        name: name.to_s.strip, sales_stage: stage_or_default(opts[:stage]),
        amount_micros: amount_micros(opts[:amount]),
        currency: opts[:currency].presence || customer.currency_preference.presence || 'USD',
        expected_close_date: parse_date(opts[:expected_close_on]),
        current_need: opts[:current_need].to_s.presence,
        next_action: opts[:next_action].to_s.presence
      )
    )
  end

  # 业绩归客户归属人；客户还没分配归属人时才落到建单的人头上。
  def belongs_attrs(customer)
    { crm_customer_id: customer.id, owner_id: customer.account_owner_id || scope.user_id,
      last_activity_at: Time.current }
  end

  def done_text(customer, opp)
    money_text = opp.amount_micros.present? ? "，预估 #{money(opp.amount_micros, opp.currency)}" : ''
    close_text = opp.expected_close_date.present? ? "，预计 #{day(opp.expected_close_date)} 成交" : ''
    "已为 #{customer.name} 建商机「#{opp.name}」（阶段 #{stage_label(opp.sales_stage)}#{money_text}#{close_text}）。" \
      '在「商机看板」和销售漏斗里能看到；建错了可以直接删。'
  end

  STAGE_LABELS = { 'NEEDS_CONFIRMED' => '需求确认', 'SAMPLING' => '样品中', 'PENDING_PAYMENT' => '待付款' }.freeze

  def stage_label(stage) = STAGE_LABELS[stage] || stage

  # 只允许建在谈阶段：WON/LOST 是结果态，由人在看板上推——
  # AI 直接建一个「已赢单」会把成交统计和提成算进去。
  def stage_or_default(stage)
    key = stage.to_s.strip.upcase
    OPEN_STAGES.include?(key) ? key : 'NEEDS_CONFIRMED'
  end

  def amount_micros(value)
    num = value.to_s.gsub(/[^\d.]/, '').to_d
    num.positive? ? (num * 1_000_000).round : nil
  end

  def parse_date(value)
    return nil if value.to_s.strip.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
