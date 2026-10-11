# 固定资产批量导入（Excel）。账套启用时把现有资产连「已提折旧」一次性搬进来。
#
# 为什么必须带已提折旧：历史资产不是今天买的，期初不把累计折旧带进来，系统会从零
# 重新提一遍，折旧费用与净值全错。模型上 accumulated_depreciation 只由计提/处置维护，
# 期初建账是唯一的例外，所以只在这里写它。
#
# 表头（中文，顺序不限，可以不在第一行——有些导出带标题行，前 5 行都扫）：
#   资产编码 | 资产名称 | 类别 | 购入日期 | 原值 | 残值率% | 折旧月数 | 已提折旧 | 使用部门 | 保管人 | 备注
#
# 逐行独立：一行错不影响其它行，错误行连行号原样报回去（财务照着改那几行再导一次）。
# 填了部门/保管人却对不上的，算这一行的错误——不静默置空：默默丢掉的归属没人看得出来。
class Erp::FixedAssetImportService
  class Error < StandardError; end

  require 'roo'

  HEADER_SCAN_ROWS = 5
  COLUMNS = {
    asset_no: %w[资产编码 资产编号 编码],
    name: %w[资产名称 名称],
    category: %w[类别 资产类别],
    purchased_at: %w[购入日期 购置日期 入账日期],
    original_value: %w[原值 资产原值 原始价值],
    residual_rate: %w[残值率 残值率% 预计残值率],
    useful_months: %w[折旧月数 使用月数 预计使用月数],
    accumulated: %w[已提折旧 累计折旧 期初累计折旧],
    department: %w[使用部门 部门],
    keeper: %w[保管人 使用人 责任人],
    remark: %w[备注 说明]
  }.freeze

  REQUIRED = { name: '资产名称', purchased_at: '购入日期', original_value: '原值' }.freeze

  def initialize(account:, path:)
    @account = account
    @path = path
  end

  # => { rows:, created:, failed: [{ row:, name:, errors: [...] }] }
  def import!
    rows = parse
    raise Error, '文件里没有数据行' if rows.empty?

    created = 0
    failed = []
    rows.each do |row|
      create_asset!(row)
      created += 1
    rescue Error, ActiveRecord::RecordInvalid => e
      failed << { row: row[:_row], name: row[:name], errors: [message_of(e)] }
    end
    { rows: rows.size, created: created, failed: failed }
  end

  # 导入模板（.xlsx）：表头 + 一行示例，财务照着填。
  def self.template_stream
    header = COLUMNS.values.map(&:first)
    sample = ['', 'SMT 贴片机', '生产设备', '2024-03-15', '480000', '5', '120', '96000', '', '', '启用日前已提 2 年']
    XlsxWriter.new(
      col_widths: [14, 24, 12, 14, 14, 10, 10, 14, 14, 12, 24],
      rows: [header.map { |text| [text, :s, :header] }, sample.map { |text| [text, :s, :text] }],
      sheet_name: '固定资产'
    ).to_stream
  end

  private

  def create_asset!(row)
    @account.erp_fixed_assets.create!(
      asset_no: row[:asset_no].presence,
      name: row[:name],
      category: category_of(row[:category]),
      purchased_at: date_of(row[:purchased_at]),
      original_value_micros: original_value_of(row),
      residual_rate: row[:residual_rate].presence || 5,
      useful_months: row[:useful_months].presence&.to_i || 60,
      accumulated_depreciation_micros: accumulated_of(row),
      department_id: department_id_of(row[:department]),
      keeper_id: keeper_id_of(row[:keeper]),
      remark: row[:remark].presence
    )
  end

  def original_value_of(row)
    micros = to_micros(row[:original_value])
    raise Error, '原值必须大于 0' unless micros.positive?

    micros
  end

  # 已提折旧不能超过可折旧总额（原值 × (1−残值率)）：超了说明表里填错，
  # 放进来净值会低于残值，往后再计提就是负数。
  def accumulated_of(row)
    micros = to_micros(row[:accumulated])
    return 0 if micros.zero?

    rate = (row[:residual_rate].presence || 5).to_d
    depreciable = (to_micros(row[:original_value]) * (1 - (rate / 100))).round
    raise Error, '已提折旧超过了可折旧总额（原值 × (1 − 残值率)），请核对' if micros > depreciable

    micros
  end

  def category_of(text)
    label = text.to_s.strip
    return 'OTHER' if label.blank?

    code = Erp::FixedAsset::CATEGORY_LABELS.key(label) || (Erp::FixedAsset::CATEGORIES.include?(label) ? label : nil)
    raise Error, "类别「#{label}」不认识，可填：#{Erp::FixedAsset::CATEGORY_LABELS.values.join('、')}" if code.nil?

    code
  end

  def date_of(value)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    raise Error, "购入日期「#{value}」读不出来，请用 2024-03-15 这种写法"
  end

  def department_id_of(text)
    name = text.to_s.strip
    return nil if name.blank?

    departments[name] || raise(Error, "使用部门「#{name}」在部门档案里找不到")
  end

  def keeper_id_of(text)
    name = text.to_s.strip
    return nil if name.blank?

    keepers[name] || raise(Error, "保管人「#{name}」在成员里找不到")
  end

  def departments
    @departments ||= @account.org_departments.pluck(:name, :id).to_h
  end

  # 中文名与 CRM 英文名都认（成员表两个名字都在用）。
  def keepers
    @keepers ||= @account.users.pluck(:name, :crm_name, :id)
                         .each_with_object({}) do |(name, crm_name, id), map|
      map[name.to_s.strip] ||= id if name.present?
      map[crm_name.to_s.strip] ||= id if crm_name.present?
    end
  end

  def message_of(error)
    return error.record.errors.full_messages.join('；') if error.is_a?(ActiveRecord::RecordInvalid) && error.record.present?

    error.message
  end

  def parse
    sheet = open_sheet
    header_row, cols = find_header(sheet)
    raise Error, "表头里找不到「#{REQUIRED[:name]}」列，请用模板的表头" if header_row.nil?

    missing = REQUIRED.reject { |key, _| cols[key] }.values
    raise Error, "表头缺少必需的列：#{missing.join('、')}" if missing.any?

    ((header_row + 1)..sheet.last_row).filter_map { |i| row_at(sheet, cols, i) }
  end

  def row_at(sheet, cols, index)
    row = cols.transform_values { |col| sheet.cell(index, col).to_s.strip }
    return nil if row[:name].blank? && row[:original_value].blank?

    row.merge(_row: index)
  end

  def open_sheet
    Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
  rescue StandardError => e
    raise Error, "读取 Excel 失败：#{e.message}"
  end

  # 表头不一定在第一行（有的导出带标题行），前几行扫一遍。
  def find_header(sheet)
    (1..[HEADER_SCAN_ROWS, sheet.last_row].min).each do |i|
      cells = (1..sheet.last_column).map { |c| sheet.cell(i, c).to_s.strip }
      cols = COLUMNS.transform_values { |names| col_of(cells, names) }.compact
      return [i, cols] if cols[:name]
    end
    [nil, {}]
  end

  def col_of(cells, names)
    idx = cells.index { |cell| names.include?(cell.delete('％%')) || names.include?(cell) }
    idx && (idx + 1)
  end

  def to_micros(value)
    return 0 if value.blank?

    (value.to_s.gsub(/[^\d.\-]/, '').to_d * 1_000_000).round
  rescue ArgumentError
    0
  end
end
