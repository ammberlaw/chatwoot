# 账簿查询：科目余额表 / 明细账 / 维度明细账。
#
# 全部**实时按凭证分录算**，不落中间表（ERP_SPEC §9.1）——只认 POSTED 凭证，
# 草稿与作废凭证不进账。金额一律本位币（base_amount_micros）。
#
# 余额方向：借方科目余额 = 借 - 贷；贷方科目余额 = 贷 - 借。分类科目的数字是下级汇总上来的。
class Erp::LedgerQueryService
  def initialize(account)
    @account = account
  end

  # 科目余额表：期初 + 本期借贷发生 + 期末，按科目树汇总。
  # 返回按 code 排序的数组，每项含 account 与四个金额（micros）。
  # exclude_closing=true 排除期末结转凭证——利润表要「结转前」的本期损益，
  # 否则结完账损益科目被冲平，利润表会显示 0（踩过）。
  def balances(from:, to:, exclude_closing: false)
    accounts = @account.erp_ledger_accounts.order(:code).to_a
    opening = grouped_sums(scope_before(from, exclude_closing: exclude_closing))
    period = grouped_sums(scope_between(from, to, exclude_closing: exclude_closing))

    rows = accounts.to_h { |account| [account.id, build_row(account, opening, period)] }
    rollup!(accounts, rows)
    accounts.map { |account| finalize_row(rows[account.id]) }
  end

  # 明细账：某科目（含下级）的逐笔分录，带累计余额，可再按维度切片。
  def entries(ledger_account:, from:, to:, dimension: nil, dimension_id: nil)
    ids = account_with_descendant_ids(ledger_account)
    opening = signed_balance(grouped_sums(scope_before(from).where(ledger_account_id: ids)), ledger_account.direction, ids)

    scope = scope_between(from, to).where(ledger_account_id: ids)
    scope = scope.where(dimension_column(dimension) => dimension_id) if dimension.present? && dimension_id.present?
    running = opening
    rows = scope.includes(:voucher, :ledger_account, :crm_customer, :mes_supplier, :crm_sales_order, :department, :member)
                .order('erp_vouchers.voucher_date ASC, erp_vouchers.voucher_no ASC, erp_voucher_lines.position ASC')
                .map do |line|
      running += signed_amount(line, ledger_account.direction)
      { line: line, balance_micros: running }
    end
    { opening_micros: opening, rows: rows, closing_micros: running }
  end

  # 维度明细账：按客户/供应商/订单/部门/业务员切片的发生额（比金蝶强的点，§9.1）。
  # 可限定科目（如「按客户看主营业务收入」）。
  def dimension_summary(dimension:, from:, to:, ledger_account: nil)
    column = dimension_column(dimension)
    scope = scope_between(from, to).where.not(column => nil)
    scope = scope.where(ledger_account_id: account_with_descendant_ids(ledger_account)) if ledger_account.present?

    sums = scope.group(column, :direction).sum(:base_amount_micros)
    keys = sums.keys.map(&:first).uniq
    labels = dimension_labels(dimension, keys)
    rows = keys.map { |key| dimension_row(key, labels[key], sums) }
    rows.sort_by { |row| -(row[:debit_micros] + row[:credit_micros]) }
  end

  private

  def dimension_row(key, name, sums)
    debit = sums[[key, Erp::VoucherLine::DEBIT]].to_i
    credit = sums[[key, Erp::VoucherLine::CREDIT]].to_i
    { id: key, name: name, debit_micros: debit, credit_micros: credit, net_micros: debit - credit }
  end

  CLOSING_SOURCE = 'Erp::PeriodClose'.freeze

  def posted_lines(exclude_closing: false)
    scope = @account.erp_voucher_lines.joins(:voucher).where(erp_vouchers: { status: Erp::Voucher::POSTED })
    return scope unless exclude_closing

    scope.where.not(erp_vouchers: { source_type: CLOSING_SOURCE })
         .or(scope.where(erp_vouchers: { source_type: nil }))
  end

  def scope_before(from, exclude_closing: false)
    posted_lines(exclude_closing: exclude_closing).where(erp_vouchers: { voucher_date: ...from })
  end

  def scope_between(from, to, exclude_closing: false)
    posted_lines(exclude_closing: exclude_closing).where(erp_vouchers: { voucher_date: from..to })
  end

  def grouped_sums(scope)
    scope.group(:ledger_account_id, :direction).sum(:base_amount_micros)
  end

  # 先只留借贷原始发生额（不带符号），汇总完再按科目自身方向折成余额——
  # 否则像「损益类(6)」这种下挂收入(贷)与费用(借)的分类科目，把子科目的带符号余额相加会把方向算反。
  def build_row(account, opening, period)
    {
      account: account,
      opening_debit_micros: opening[[account.id, Erp::VoucherLine::DEBIT]].to_i,
      opening_credit_micros: opening[[account.id, Erp::VoucherLine::CREDIT]].to_i,
      debit_micros: period[[account.id, Erp::VoucherLine::DEBIT]].to_i,
      credit_micros: period[[account.id, Erp::VoucherLine::CREDIT]].to_i
    }
  end

  def finalize_row(row)
    direction = row[:account].direction
    row[:opening_micros] = directional(direction, row[:opening_debit_micros], row[:opening_credit_micros])
    row[:closing_micros] = directional(
      direction,
      row[:opening_debit_micros] + row[:debit_micros],
      row[:opening_credit_micros] + row[:credit_micros]
    )
    row
  end

  def directional(direction, debit, credit)
    direction == Erp::VoucherLine::DEBIT ? debit - credit : credit - debit
  end

  ROLLUP_KEYS = %i[opening_debit_micros opening_credit_micros debit_micros credit_micros].freeze

  # 分类科目自身不记账，数字全靠下级汇总——自底向上累加到每一层父科目。
  def rollup!(accounts, rows)
    by_depth = accounts.sort_by { |account| -account.code.to_s.length }
    by_depth.each do |account|
      next if account.parent_id.blank?

      parent_row = rows[account.parent_id]
      next if parent_row.blank?

      child = rows[account.id]
      ROLLUP_KEYS.each do |key|
        parent_row[key] += child[key]
      end
    end
  end

  def account_with_descendant_ids(account)
    return [] if account.blank?

    ids = [account.id]
    frontier = [account.id]
    while frontier.any?
      children = @account.erp_ledger_accounts.where(parent_id: frontier).pluck(:id)
      ids.concat(children)
      frontier = children
    end
    ids
  end

  def signed_balance(sums, direction, ids)
    debit = ids.sum { |id| sums[[id, Erp::VoucherLine::DEBIT]].to_i }
    credit = ids.sum { |id| sums[[id, Erp::VoucherLine::CREDIT]].to_i }
    directional(direction, debit, credit)
  end

  def signed_amount(line, direction)
    same_side = line.direction == direction
    same_side ? line.base_amount_micros : -line.base_amount_micros
  end

  DIMENSION_COLUMNS = {
    'customer' => :crm_customer_id, 'supplier' => :mes_supplier_id, 'order' => :crm_sales_order_id,
    'department' => :department_id, 'member' => :member_id
  }.freeze

  def dimension_column(dimension)
    DIMENSION_COLUMNS.fetch(dimension.to_s)
  end

  # 维度 → [关联名, 显示字段]；业务员单独走（CRM 英文名优先）。
  LABEL_SOURCES = {
    'customer' => [:crm_customers, :name], 'supplier' => [:mes_suppliers, :name],
    'order' => [:crm_sales_orders, :order_no], 'department' => [:org_departments, :name]
  }.freeze

  def dimension_labels(dimension, ids)
    return {} if ids.empty?
    return member_labels(ids) if dimension.to_s == 'member'

    association, field = LABEL_SOURCES.fetch(dimension.to_s)
    @account.public_send(association).where(id: ids).pluck(:id, field).to_h
  end

  def member_labels(ids)
    User.where(id: ids).pluck(:id, :crm_name, :name).to_h { |id, crm_name, name| [id, crm_name.presence || name] }
  end
end
