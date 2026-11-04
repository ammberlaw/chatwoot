# 工资表 Excel 导入。吃财务现在手上那两张表，格式原样不动：
#
#   车间版   每人两行（表头+数据交替），有「工龄补贴/其它」「优秀员工奖」
#   办公室版 有「绩效工资」「入职日期」，补贴不按满勤折算
#
# 三条口径：
#   1. **只读原始项**（基本工资/补贴/出勤天数/加班/扣款/社保），
#      出勤工资、应发、实发一律系统重算——表里的公式被人改坏了也带不进来。
#   2. **按表头文字定位列，不写死列号**。两张表列序不同，而且「基本工资」
#      「加班费标准」各出现两次（前者有一列整列是空的，后者分属平时/周末）。
#   3. 人按姓名对系统账号，**对不上也照样录**：车间 38 人里 33 个没有账号，
#      因为没账号就录不进来的话这张表就没法用了。
class Crm::PayrollImportService
  class Error < StandardError; end

  require 'roo'

  NAME_HEADER = '姓名'.freeze

  # 表头（去掉空格与换行后）→ 字段。重名的那两个单独处理，见 #map_columns。
  MONEY = {
    '底薪合计' => :base_total_micros,
    '职位补贴' => :position_allowance_micros,
    '工龄补贴/其它' => :seniority_allowance_micros,
    '伙食补贴' => :meal_allowance_micros,
    '外宿补助' => :lodging_allowance_micros,
    '外宿补贴' => :lodging_allowance_micros,   # 两张表用词不同
    '全勤奖' => :attendance_bonus_micros,
    '优秀员工奖' => :excellent_bonus_micros,
    '绩效工资' => :performance_salary_micros,
    '提成工资' => :commission_salary_micros,
    '迟到扣款' => :late_deduction_micros,
    '未打卡扣款' => :absence_deduction_micros,
    '社保扣款' => :social_insurance_micros,
    '个税扣款' => :income_tax_micros
  }.freeze

  DAYS = {
    '实出勤（天）' => :actual_days,
    '应出勤（天）' => :expected_days,
    '请假（天）' => :leave_days
  }.freeze

  TEXT = { '职位' => :position, '在职状态' => :employment_status }.freeze

  # 表里已算好的结果：不当数据用，只拿来和系统重算的值对账。
  # 对不上的差额落到「个别调整」里并写明来源，别让它凭空消失，也别藏进公式。
  AUDIT = { '应发工资' => :_xls_gross, '实发工资' => :_xls_net }.freeze

  def initialize(account:, user:, path:, period_month:, template: nil, title: nil)
    @account = account
    @user = user
    @path = path
    @period_month = period_month.to_date.beginning_of_month
    @template = template
    @title = title
  end

  def import!
    rows = parse
    raise Error, '文件里没有数据行（找不到「姓名」表头，或表头下没有数据）' if rows.empty?

    tpl = @template.presence || detect_template(rows)
    sheet = nil
    ActiveRecord::Base.transaction do
      sheet = @account.crm_payroll_sheets.create!(
        period_month: @period_month, template: tpl, created_by_id: @user&.id,
        title: @title.presence || default_title(tpl)
      )
      build_items(sheet, rows)
    end
    sheet
  end

  private

  def default_title(tpl)
    "#{@period_month.strftime('%-m月')}#{Crm::PayrollSheet::TEMPLATES[tpl]}工资表"
  end

  # 有「工龄补贴」或「优秀员工奖」＝车间；有「绩效工资」＝办公室。都没有时按办公室
  # （办公室公式不含那个 +3，少算总比多算安全）。
  def detect_template(rows)
    keys = rows.first[:_headers]
    return 'WORKSHOP' if keys.include?('工龄补贴/其它') || keys.include?('优秀员工奖')

    'OFFICE'
  end

  def build_items(sheet, rows)
    known = @account.account_users.includes(:user).index_by { |au| au.user.name.to_s.strip }
    rows.each_with_index do |row, i|
      item = sheet.items.new(account: @account, sort_order: i, employee_name: row[:employee_name])
      item.user_id = known[row[:employee_name]]&.user_id
      row.each { |k, v| item[k] = v unless k.to_s.start_with?('_') || k == :employee_name }
      item.compute!
      reconcile!(item, row[:_xls_gross])
      item.save!
    end
  end

  # 和表里原有的应发对账：差 1 分以上就把差额记进「个别调整」，并写明是导入时补的。
  # 这样历史表能一分不差地复现，同时差异有名有姓地留在账上，不像原来那样藏在公式里。
  def reconcile!(item, xls_gross)
    return if xls_gross.blank?

    diff = xls_gross - item.gross_pay_micros
    return if diff.abs < 10_000 # 1 分

    item.adjustment_micros = diff
    item.adjustment_reason = "导入时与原表差 #{(diff / 1_000_000.0).round(2)} 元，原因待核"
    item.compute!
  end

  # 扫全表：遇到「姓名」所在行就当表头（车间表每两行重复一次），其后的行按它解析。
  def parse
    xls = Roo::Spreadsheet.open(@path)
    out = []
    cols = nil
    (1..xls.last_row).each do |r|
      cells = (1..xls.last_column).map { |c| xls.cell(r, c) }
      if header_row?(cells)
        cols = map_columns(cells)
        next
      end
      next if cols.nil?

      row = extract(cells, cols)
      out << row if row
    end
    out
  rescue Roo::Error, Zip::Error => e
    raise Error, "读不开这个文件：#{e.message}"
  end

  def header_row?(cells) = cells.any? { |c| norm(c) == NAME_HEADER }

  def norm(v) = v.to_s.gsub(/[[:space:]]/, '')

  # 列名 → 列号。重名的两个按位置定：
  #   「基本工资」两列（其中一列整列空）→ 取靠后那个，数据在它上面。
  #   「加班费标准」两列 → 紧跟在各自的加班时间列后面，按相邻关系配对。
  def map_columns(cells)
    idx = {}
    cells.each_with_index do |c, i|
      n = norm(c)
      next if n.blank?

      (idx[n] ||= []) << i
    end
    {
      headers: idx.keys,
      name: idx[NAME_HEADER]&.first,
      basic: idx['基本工资']&.last,
      weekday_ot: ot_trio(idx, '平时加班时间'),
      weekend_ot: ot_trio(idx, '周末加班（天）') || ot_trio(idx, '周末加班'),
      money: MONEY.filter_map { |h, f| [f, idx[h].first] if idx[h] },
      audit: AUDIT.filter_map { |h, f| [f, idx[h].first] if idx[h] },
      days: DAYS.filter_map { |h, f| [f, idx[h].first] if idx[h] },
      text: TEXT.filter_map { |h, f| [f, idx[h].first] if idx[h] },
      hire_date: idx['入职日期']&.first
    }
  end

  # 加班三件套：时间列、它右边的标准列、再右边的工资列。
  # 不按列名找「加班费标准」——那个名字出现两次，按相邻关系配才不会串。
  def ot_trio(idx, hours_header)
    h = idx[hours_header]&.first
    h && { hours: h, rate: h + 1 }
  end

  def extract(cells, cols)
    name = cells[cols[:name]].to_s.strip if cols[:name]
    return nil if name.blank? || name == NAME_HEADER

    row = { employee_name: name, _headers: cols[:headers] }
    cols[:text].each { |f, i| row[f] = cells[i].to_s.strip.presence }
    row[:hire_date] = to_date(cells[cols[:hire_date]]) if cols[:hire_date]
    row[:basic_salary_micros] = money(cells[cols[:basic]]) if cols[:basic]
    cols[:money].each { |f, i| row[f] = money(cells[i]) }
    cols[:audit].each { |f, i| row[f] = money(cells[i]) }
    cols[:days].each  { |f, i| row[f] = num(cells[i]) }
    %i[weekday weekend].each do |kind|
      t = cols[:"#{kind}_ot"]
      next unless t

      row[:"#{kind}_ot_hours"] = num(cells[t[:hours]])
      row[:"#{kind}_ot_rate_micros"] = money(cells[t[:rate]])
      # 加班工资不读表里那一列：时间×标准由系统算，和出勤工资同一条口径。
      row[:"#{kind}_ot_pay_micros"] = (row[:"#{kind}_ot_hours"] * row[:"#{kind}_ot_rate_micros"]).round
    end
    row
  end

  def money(v) = (num(v) * 1_000_000).round

  def num(v)
    return 0.to_d if v.blank?
    return v.to_d if v.is_a?(Numeric)

    v.to_s.gsub(/[,，\s¥￥元]/, '')[/-?\d+(\.\d+)?/].to_d
  end

  def to_date(v)
    return v if v.is_a?(Date)
    return v.to_date if v.respond_to?(:to_date) && !v.is_a?(String)

    Date.parse(v.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
