# 工资表的一行＝一个人这个月的账。
# ⚠️ user_id 允许为空：车间 38 人里 33 个在系统没有账号，不能因此录不进来。
# == Schema Information
#
# Table name: crm_payroll_items
#
#  id                         :bigint           not null, primary key
#  absence_deduction_micros   :bigint           default(0), not null
#  actual_days                :decimal(6, 2)    default(0.0), not null
#  adjustment_micros          :bigint           default(0), not null
#  adjustment_reason          :string
#  attendance_bonus_micros    :bigint           default(0), not null
#  attendance_pay_micros      :bigint           default(0), not null
#  base_total_micros          :bigint           default(0), not null
#  basic_salary_micros        :bigint           default(0), not null
#  commission_salary_micros   :bigint           default(0), not null
#  employee_name              :string           not null
#  employment_status          :string
#  excellent_bonus_micros     :bigint           default(0), not null
#  expected_days              :decimal(6, 2)    default(0.0), not null
#  gross_pay_micros           :bigint           default(0), not null
#  hire_date                  :date
#  income_tax_micros          :bigint           default(0), not null
#  late_deduction_micros      :bigint           default(0), not null
#  leave_days                 :decimal(6, 2)    default(0.0), not null
#  lodging_allowance_micros   :bigint           default(0), not null
#  meal_allowance_micros      :bigint           default(0), not null
#  net_pay_micros             :bigint           default(0), not null
#  performance_salary_micros  :bigint           default(0), not null
#  position                   :string
#  position_allowance_micros  :bigint           default(0), not null
#  remark                     :text
#  seniority_allowance_micros :bigint           default(0), not null
#  social_insurance_micros    :bigint           default(0), not null
#  sort_order                 :integer          default(0), not null
#  weekday_ot_hours           :decimal(8, 2)    default(0.0), not null
#  weekday_ot_pay_micros      :bigint           default(0), not null
#  weekday_ot_rate_micros     :bigint           default(0), not null
#  weekend_ot_hours           :decimal(8, 2)    default(0.0), not null
#  weekend_ot_pay_micros      :bigint           default(0), not null
#  weekend_ot_rate_micros     :bigint           default(0), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  crm_payroll_sheet_id       :bigint           not null
#  user_id                    :bigint
#
# Indexes
#
#  idx_payroll_items_on_sheet             (crm_payroll_sheet_id)
#  index_crm_payroll_items_on_account_id  (account_id)
#  index_crm_payroll_items_on_user_id     (user_id)
#
class Crm::PayrollItem < ApplicationRecord
  belongs_to :account
  belongs_to :sheet, class_name: 'Crm::PayrollSheet', foreign_key: :crm_payroll_sheet_id,
                     inverse_of: :items
  belongs_to :user, optional: true

  validates :employee_name, presence: true

  scope :ordered, -> { order(:sort_order, :id) }

  # 按模板算出 出勤工资 / 应发 / 实发，三个值都落库。
  # 公式照搬现行 Excel（2026-09 两张表逐行验算过，分毫不差）：
  #
  #   车间    出勤工资 = (职位补贴+工龄补贴)/应出勤 × min(实出勤+3, 应出勤) + 基本工资/应出勤 × 实出勤
  #   办公室  出勤工资 = (基本工资+职位补贴)/应出勤 × 实出勤
  #
  # 车间那个 +3 是「补贴按满勤给」，但原表公式没封顶，满勤的人会算成 25/22 天、
  # 补贴超发 13.6%。2026-09 表里有人手工把满勤那两行的 +3 删掉——说明本意就是封顶，
  # 只是没写进公式。这里补上 min()：34 个实出勤≤19 天的人结果完全不变，
  # 满勤两人算出 2450，与手改值一致。办公室没有这一条。
  # 「底薪合计」是合同数，只展示不参与计算——实测它和 基本工资+职位补贴 对不上。
  # 请假天数不单独扣钱：请了假实出勤就少，出勤工资自然低，再扣一次是重复。
  def compute!
    self.attendance_pay_micros = attendance_pay
    self.gross_pay_micros = gross_pay
    self.net_pay_micros = gross_pay_micros - social_insurance_micros - income_tax_micros
    self
  end

  private

  def attendance_pay
    days = expected_days.to_d
    return 0 if days.zero?

    if sheet.template == 'WORKSHOP'
      allowance = position_allowance_micros + seniority_allowance_micros
      allowance_days = [actual_days.to_d + 3, days].min
      (allowance / days * allowance_days + basic_salary_micros / days * actual_days.to_d).round
    else
      ((basic_salary_micros + position_allowance_micros) / days * actual_days.to_d).round
    end
  end

  # 应发＝各项补贴/奖金/绩效/提成 + 加班 + 出勤工资 + 个别调整 − 迟到 − 未打卡。
  # 个别调整是规则外的加减（可正可负），必须写原因——原表那种把 +29 藏进公式的做法
  # 事后谁也说不清是什么钱。
  def gross_pay
    meal_allowance_micros + lodging_allowance_micros + attendance_bonus_micros +
      excellent_bonus_micros + performance_salary_micros + commission_salary_micros +
      weekday_ot_pay_micros + weekend_ot_pay_micros + attendance_pay_micros +
      adjustment_micros - late_deduction_micros - absence_deduction_micros
  end
end
