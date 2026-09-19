# 固定资产折旧：按月一键计提 + 处置/报废。
#
# 计提：在用资产逐台算直线法月折旧（提到残值为止，最后一个月自动补差额），
# 汇总成**一张**折旧凭证（借 折旧与摊销 / 贷 累计折旧），而不是一台一张。
# 幂等：一台资产一个期间只有一条计提记录（唯一索引兜底），重复点不会翻倍。
class Erp::DepreciationService
  class Error < StandardError; end

  DEPRECIATION_TYPE = 'DEPRECIATION'.freeze       # 折旧费用科目（660204）
  ACCUM_TYPE = 'ACCUM_DEPRECIATION'.freeze        # 累计折旧（1602）
  FIXED_ASSET_TYPE = 'FIXED_ASSET'.freeze         # 固定资产（1601）
  DISPOSAL_CODE = '6115'.freeze                   # 资产处置损益

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 返回 { period:, count:, amount_micros:, voucher_no: }
  def run!(period)
    validate_period!(period)
    rows = pending_assets(period).filter_map { |asset| plan_for(asset) }
    return { period: period, count: 0, amount_micros: 0, voucher_no: nil } if rows.empty?

    commit!(rows, period)
  end

  # 处置/报废：结转累计折旧与净值，处置收入与净值差额进资产处置损益。
  def dispose!(asset, disposed_at:, income_micros: 0, scrapped: false)
    ActiveRecord::Base.transaction do
      asset.lock! # 行锁+锁内复检：防并发/双击重复处置(生成两张处置凭证)，并与并发折旧串行
      raise Error, '该资产已处置或报废' unless asset.status == Erp::FixedAsset::IN_USE

      period = disposed_at.to_date.strftime('%Y-%m')
      raise Error, "会计期间 #{period} 已结账，不能处置" if Erp::FiscalPeriod.closed?(@account, period)

      voucher = build_disposal_voucher(asset, disposed_at, income_micros)
      asset.update!(
        status: scrapped ? Erp::FixedAsset::SCRAPPED : Erp::FixedAsset::DISPOSED,
        disposed_at: disposed_at, disposal_income_micros: income_micros
      )
      { asset: asset, voucher_no: voucher&.voucher_no }
    end
  end

  # 折旧/处置凭证还是草稿就被作废或删除时，把资产侧账一起退回去——
  # 计提记录和累计折旧是跟凭证同事务写入的，光去掉凭证会留下「资产已折旧、总账没入账」，
  # 而且该期间的计提记录还在，重新计提会返回 0 张，这个月的折旧就永远丢了。
  def rollback_voucher!(voucher)
    entries = @account.erp_depreciation_entries.where(voucher_id: voucher.id).includes(:fixed_asset)
    entries.find_each do |entry|
      asset = entry.fixed_asset
      asset.lock!
      asset.update!(accumulated_depreciation_micros: asset.accumulated_depreciation_micros - entry.amount_micros)
      entry.destroy!
    end
    rollback_disposal!(voucher) if entries.empty?
  end

  private

  # 处置凭证（source_id=资产 id、无计提记录）：把资产退回在用，允许改对了再处置。
  def rollback_disposal!(voucher)
    asset = @account.erp_fixed_assets.find_by(id: voucher.source_id)
    return if asset.blank? || asset.status == Erp::FixedAsset::IN_USE

    asset.update!(status: Erp::FixedAsset::IN_USE, disposed_at: nil, disposal_income_micros: 0)
  end

  def validate_period!(period)
    raise Error, '会计期间格式应为 YYYY-MM' unless period.to_s.match?(/\A\d{4}-\d{2}\z/)
    raise Error, "会计期间 #{period} 已结账，不能再计提折旧" if Erp::FiscalPeriod.closed?(@account, period)
  end

  def commit!(rows, period)
    total = rows.sum { |row| row[:amount] }
    ActiveRecord::Base.transaction do
      voucher = build_voucher(period, total)
      rows.each { |row| commit_row(row, period, voucher) }
      { period: period, count: rows.size, amount_micros: total, voucher_no: voucher&.voucher_no }
    end
  end

  # 已到使用月份、还没提满、且该期间没提过的在用资产。
  def pending_assets(period)
    done = @account.erp_depreciation_entries.where(period: period).pluck(:fixed_asset_id)
    @account.erp_fixed_assets.in_use.where.not(id: done)
            .select { |asset| asset.purchased_at.strftime('%Y-%m') <= period && asset.remaining_depreciable_micros.positive? }
  end

  # 本月提多少：正常提月折旧额；剩余不足一个月的，把尾数一次提完。
  def plan_for(asset)
    amount = [asset.monthly_depreciation_micros, asset.remaining_depreciable_micros].min
    return nil if amount <= 0

    { asset: asset, amount: amount }
  end

  def commit_row(row, period, voucher)
    asset = row[:asset]
    asset.lock! # 行锁+重读：累计折旧读-加-写在锁内完成，与并发处置/其它计提串行，防覆盖
    @account.erp_depreciation_entries.create!(
      fixed_asset_id: asset.id, period: period, amount_micros: row[:amount], voucher_id: voucher&.id
    )
    asset.update!(accumulated_depreciation_micros: asset.accumulated_depreciation_micros + row[:amount])
  end

  def build_voucher(period, total)
    expense = account_by_type(DEPRECIATION_TYPE)
    accum = account_by_type(ACCUM_TYPE)
    raise Error, '找不到「折旧费用」或「累计折旧」科目，请先在科目表里配置' if expense.blank? || accum.blank?

    create_voucher(
      date: Date.parse("#{period}-01").end_of_month,
      summary: "#{period} 计提固定资产折旧",
      lines: [
        line(expense, Erp::VoucherLine::DEBIT, total, '计提折旧'),
        line(accum, Erp::VoucherLine::CREDIT, total, '计提折旧')
      ]
    )
  end

  # 处置分录：借 累计折旧 + 借/贷 处置损益 + 借 货币资金(处置收入) / 贷 固定资产原值
  def build_disposal_voucher(asset, disposed_at, income_micros)
    fixed = account_by_type(FIXED_ASSET_TYPE)
    accum = account_by_type(ACCUM_TYPE)
    disposal = @account.erp_ledger_accounts.find_by(code: DISPOSAL_CODE)
    raise Error, '找不到固定资产/累计折旧/资产处置损益科目' if fixed.blank? || accum.blank? || disposal.blank?

    lines = disposal_lines(asset, income_micros, fixed: fixed, accum: accum, disposal: disposal)
    create_voucher(date: disposed_at, summary: "处置固定资产 #{asset.asset_no} #{asset.name}", lines: lines,
                   source_id: asset.id)
  end

  def disposal_lines(asset, income_micros, fixed:, accum:, disposal:)
    net = asset.net_value_micros
    lines = []
    lines << line(accum, Erp::VoucherLine::DEBIT, asset.accumulated_depreciation_micros, '转销累计折旧') if asset.accumulated_depreciation_micros.positive?
    lines << line(cash_or_disposal(disposal), Erp::VoucherLine::DEBIT, income_micros, '处置收入') if income_micros.positive?
    gap = net - income_micros
    if gap.positive?
      lines << line(disposal, Erp::VoucherLine::DEBIT, gap, '处置净损失')
    elsif gap.negative?
      lines << line(disposal, Erp::VoucherLine::CREDIT, gap.abs, '处置净收益')
    end
    lines << line(fixed, Erp::VoucherLine::CREDIT, asset.original_value_micros, '转销资产原值')
    lines
  end

  # 处置收入先记到货币资金（有银行账户就用第一个映射科目），没有就并入处置损益科目。
  def cash_or_disposal(disposal)
    @account.erp_cash_accounts.active.where.not(ledger_account_id: nil).first&.ledger_account || disposal
  end

  def account_by_type(type)
    @account.erp_ledger_accounts.active.leaves.find_by(account_type: type)
  end

  def line(ledger_account, direction, amount_micros, summary)
    { ledger_account_id: ledger_account.id, direction: direction, amount_micros: amount_micros,
      summary: summary, currency: 'CNY', exchange_rate: 1 }
  end

  # 折旧与处置凭证都直接生成**待过账**，与自动凭证一个哲学：系统只做单据，记账由财务点。
  # 处置凭证带 source_id=资产 id（草稿被删时靠它回滚资产状态）；计提凭证靠计提记录反查，不用带。
  def create_voucher(date:, summary:, lines:, source_id: nil)
    voucher = @account.erp_vouchers.create!(
      voucher_date: date, summary: summary, status: Erp::Voucher::DRAFT,
      prepared_by_id: @user&.id, source_type: 'Erp::Depreciation', source_id: source_id,
      lines_attributes: lines.each_with_index.map { |row, index| row.merge(position: index) }
    )
    voucher.refresh_totals!
    voucher
  end
end
