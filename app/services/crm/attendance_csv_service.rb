# 考勤汇总导出 CSV（供 HR 对接工资）。含 UTF-8 BOM，Excel 直接打开不乱码。
class Crm::AttendanceCsvService
  require 'csv'

  HEADERS = %w[姓名 应到 已打卡 迟到 早退 旷工 请假 外勤].freeze

  def initialize(rows:, range:)
    @rows = rows
    @range = range
  end

  def generate
    body = CSV.generate do |csv|
      csv << ["考勤汇总 #{@range.first} ~ #{@range.last}"]
      csv << HEADERS
      @rows.each { |r| csv << row_values(r) }
    end
    "﻿#{body}"
  end

  private

  def row_values(row)
    [row[:name], row[:expected], row[:present], row[:late],
     row[:early_leave], row[:absent], row[:leave], row[:field]]
  end
end
