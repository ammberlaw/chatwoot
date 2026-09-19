# 费用报销的财务侧：把「OA 审批通过」接到「付钱 + 入账 + 归集成本」。
#
# 待打款 = 模板标了 erp_expense 的审批单 + 状态 approved + 还没有未作废的打款单。
class Erp::ExpensePayoutService
  # OA 报销表单的「费用类型」→ 默认费用科目（国标码）。财务在打款弹窗里可改，这里只做带出。
  # 交通归差旅费：科目表没单列交通费，硬加一个科目不如复用（差旅费本就含市内交通）。
  CATEGORY_ACCOUNT_CODES = {
    '差旅' => '660104', '交通' => '660104', '招待' => '660103',
    '办公' => '660202', '其他' => '660199'
  }.freeze
  FALLBACK_ACCOUNT_CODE = '660199'.freeze

  def initialize(account)
    @account = account
  end

  # 审批通过、尚未打款的报销单。
  def pending_requests
    paid_ids = @account.erp_expense_payouts.normal.select(:oa_approval_request_id)
    @account.oa_approval_requests
            .joins(:template)
            .where(status: 'approved', oa_approval_templates: { erp_expense: true })
            .where.not(id: paid_ids)
            .includes(:applicant, :department, :template)
            .order(updated_at: :desc)
  end

  # 表单里 type=amount 的第一个字段就是报销金额（模板约定，与备用金台账联动同一口径）。
  def self.request_amount_micros(request)
    key = amount_field_key(request.template)
    return nil if key.blank?

    parse_micros((request.form_data || {})[key])
  end

  def self.amount_field_key(template)
    Array(template&.form_fields).find { |f| f['type'] == 'amount' }&.dig('key')
  end

  def self.parse_micros(value)
    amount = BigDecimal(value.to_s)
    amount.positive? ? (amount * 1_000_000).round : nil
  rescue ArgumentError, TypeError
    nil
  end

  def self.request_category(request)
    (request.form_data || {})['category'].to_s.presence
  end

  # 费用类型对应的默认科目（找不到就落「其他销售费用」，再找不到返回 nil 让财务自己选）。
  # 按 code 缓存：待打款列表会逐条问建议科目，不缓存就是一条单据两次 find_by。
  def default_expense_account(category)
    code = CATEGORY_ACCOUNT_CODES[category.to_s] || FALLBACK_ACCOUNT_CODE
    account_cache[code] ||= account_cache[FALLBACK_ACCOUNT_CODE]
  end

  # 费用类型就那几种，一次把用得到的科目捞齐（含兜底科目）。
  def account_cache
    @account_cache ||= begin
      codes = CATEGORY_ACCOUNT_CODES.values.uniq + [FALLBACK_ACCOUNT_CODE]
      @account.erp_ledger_accounts.active.where(code: codes).index_by(&:code)
    end
  end

  # 挂了订单的报销进订单成本台账；改单时按 source 覆盖，取消挂单时删掉。
  # source 唯一索引（account_id, source_type, source_id）保证一张打款单最多一行成本。
  def sync_order_cost(payout)
    existing = @account.erp_order_costs.find_by(source_type: payout.class.name, source_id: payout.id)
    if payout.crm_sales_order_id.blank? || payout.status == Erp::ExpensePayout::VOID
      existing&.destroy
      return nil
    end

    return existing.tap { |row| row.update!(cost_attrs(payout)) } if existing

    @account.erp_order_costs.create!(
      cost_attrs(payout).merge(source_type: payout.class.name, source_id: payout.id,
                               created_by_id: payout.recorded_by_id)
    )
  end

  # 打款：落单 + 三个副作用（出纳流水 / 待过账凭证 / 挂订单的成本行），要么一起成要么全不动。
  # 通知放在事务外——事务回滚了就不该有「已打款」的通知发出去。
  def pay!(attrs, actor:)
    payout = @account.erp_expense_payouts.new(attrs)
    payout.recorded_by_id = actor&.id
    ActiveRecord::Base.transaction do
      payout.save!
      apply_side_effects(payout, actor)
    end
    notify_paid(payout)
    payout
  end

  # 改单：金额/科目/账户/挂单都可能变，三个副作用整体重算（流水按净额冲旧记新）。
  def update_payout!(payout, attrs, actor:)
    ActiveRecord::Base.transaction do
      # 换审批单＝另一张单，不许在原记录上改（否则原单又变回「待打款」且流水对不上来源）。
      payout.update!(attrs.except(:oa_approval_request_id, 'oa_approval_request_id'))
      apply_side_effects(payout, actor)
    end
    payout
  end

  # 作废：状态 + 流水冲销 + 成本行删除同一事务；凭证另算——已过账的动不了，
  # 返回它的凭证号让页面提示财务去红冲。账套锁串行化并发/重复作废。
  def void!(payout, actor:)
    posted_voucher_no = nil
    Erp::AccountLock.with_account_lock(@account.id, "expense_payout:#{payout.id}") do
      ActiveRecord::Base.transaction do
        payout.update!(status: Erp::ExpensePayout::VOID)
        Erp::CashLedgerService.new(@account, actor).reverse_for(payout)
        sync_order_cost(payout)
      end
      posted_voucher_no = Erp::AutoVoucherService.new(@account).void_for(payout)
    end
    posted_voucher_no
  end

  # 打款完成通知报销人：钱什么时候到账，员工最关心这个。
  def notify_paid(payout)
    applicant = payout.applicant
    return if applicant.blank?

    Mes::Notifier.notify(
      account: @account, recipients: applicant.id, kind: 'erp_expense_paid',
      title: "报销已打款 #{format('%.2f', payout.amount_micros / 1_000_000.0)} 元",
      body: "#{payout.approval_request&.title}：已于 #{payout.paid_at.strftime('%Y-%m-%d')} 从「#{payout.cash_account&.name}」付出"
    )
  end

  private

  def apply_side_effects(payout, actor)
    Erp::CashLedgerService.new(@account, actor).sync_for(payout, direction: Erp::CashTransaction::OUT)
    Erp::AutoVoucherService.new(@account).for_expense_payout(payout)
    sync_order_cost(payout)
  end

  def cost_attrs(payout)
    {
      crm_sales_order_id: payout.crm_sales_order_id,
      cost_type: payout.cost_type.presence || 'EXPENSE',
      amount_micros: payout.amount_micros,
      currency: payout.currency, exchange_rate: payout.exchange_rate,
      happened_at: payout.paid_at,
      remark: "报销 #{payout.payout_no} · #{payout.applicant&.name}"
    }
  end
end
