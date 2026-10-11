# 开账体检：ERP 能不能出报表，卡在这几件事上。
#
# 功能齐了不等于账开了。没人建会计期间、没录期初、没给订单建应收台账、不点过账时，
# 系统会天天正确地生成凭证，而科目余额 / 总账 / 报表永远是空的——界面上看起来像
# 「ERP 没跑起来」，可卡的不是功能，是这几个人工动作没人做。
# 把它们摆到财务看板上，缺哪件一眼看见，别等月底发现报表是空的。
class Erp::OpeningReadiness
  # 待建账口径：PENDING_CONFIRMATION 还没确认、CANCELLED 已取消，都不该进应收。
  UNCONFIRMED_STATUSES = %w[PENDING_CONFIRMATION CANCELLED].freeze

  def initialize(account)
    @account = account
  end

  def call
    {
      fiscal_start_date: fiscal_start_date,
      fiscal_period_count: @account.erp_fiscal_periods.count,
      opening_balance_ready: opening_balance_ready?,
      pending_receivable_count: pending_order_scope.count,
      draft_voucher_count: voucher_counts[Erp::Voucher::DRAFT].to_i,
      posted_voucher_count: voucher_counts[Erp::Voucher::POSTED].to_i
    }
  end

  # 待建账订单（已确认、尚无应收台账、且在会计启用日之后）。
  # 应收台账页的「待建账」清单与财务看板的这个数**必须是同一个 scope**——
  # 两处各写一份，早晚变成「角标 318、清单 200」那种对不上的数。
  def pending_order_scope
    cutoff = fiscal_start_date
    cutoff ? unfiltered_pending_scope.where(order_date: cutoff.beginning_of_day..) : unfiltered_pending_scope
  end

  # 不做启用日切的全量待建账（设置页要用它报「被日切挡掉多少张历史单」）。
  def unfiltered_pending_scope
    built_ids = @account.erp_receivables.where.not(crm_sales_order_id: nil).select(:crm_sales_order_id)
    @account.crm_sales_orders.where.not(status: UNCONFIRMED_STATUSES).where.not(id: built_ids)
  end

  def fiscal_start_date
    @fiscal_start_date ||= Erp::Setting.for_account(@account).fiscal_start_date
  end

  private

  def opening_balance_ready?
    @account.erp_vouchers
            .where(source_type: Erp::OpeningBalanceService::SOURCE_TYPE)
            .where.not(status: Erp::Voucher::VOID)
            .exists?
  end

  def voucher_counts
    @voucher_counts ||= @account.erp_vouchers.group(:status).count
  end
end
