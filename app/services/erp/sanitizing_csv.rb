# CSV 公式注入防护：Excel 会把 = + - @ 开头的单元格当公式执行。
# 审计包里的客户/供应商名、摘要都是用户可控文本，而这个包就是发给事务所在 Excel 里开的——
# 风险单元格前垫单引号按文本处理；纯数字（含负数金额）不动。
class Erp::SanitizingCsv
  RISKY_PREFIX = /\A[=+\-@]/
  NUMERIC = /\A-?\d+(\.\d+)?\z/

  def initialize(csv)
    @csv = csv
  end

  def <<(row)
    @csv << row.map { |cell| risky?(cell) ? "'#{cell}" : cell }
  end

  private

  def risky?(cell)
    cell.is_a?(String) && cell.match?(RISKY_PREFIX) && !cell.match?(NUMERIC)
  end
end
