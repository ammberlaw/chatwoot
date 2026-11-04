# 月度工资表：一个月 + 一套模板 = 一张表，财务/人事核算用。
# == Schema Information
#
# Table name: crm_payroll_sheets
#
#  id              :bigint           not null, primary key
#  confirmed_at    :datetime
#  period_month    :date             not null
#  remark          :text
#  status          :string           default("DRAFT"), not null
#  template        :string           not null
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  confirmed_by_id :bigint
#  created_by_id   :bigint
#
# Indexes
#
#  idx_on_account_id_period_month_template_f436d8ba50  (account_id,period_month,template)
#  index_crm_payroll_sheets_on_account_id              (account_id)
#
class Crm::PayrollSheet < ApplicationRecord
  # 两套算法，差别只在「出勤工资」怎么折算（见 PayrollItem#compute!）：
  # 车间的补贴按 实出勤+3 天给（满勤口径），办公室的一律按实出勤。
  TEMPLATES = { 'WORKSHOP' => '车间', 'OFFICE' => '办公室 / 业务' }.freeze
  STATUSES  = { 'DRAFT' => '核算中', 'CONFIRMED' => '已确认' }.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :confirmed_by, class_name: 'User', optional: true
  has_many :items, class_name: 'Crm::PayrollItem', foreign_key: :crm_payroll_sheet_id,
                   dependent: :destroy, inverse_of: :sheet

  validates :period_month, presence: true
  validates :template, inclusion: { in: TEMPLATES.keys }
  validates :status, inclusion: { in: STATUSES.keys }

  scope :ordered, -> { order(period_month: :desc, id: :desc) }

  def template_label = TEMPLATES[template]
  def status_label   = STATUSES[status]
  def confirmed?     = status == 'CONFIRMED'

  # 确认后锁死：工资表一旦确认就是账，再改会和已发的钱对不上。
  def editable? = !confirmed?

  def total_gross_micros = items.sum(:gross_pay_micros)
  def total_net_micros   = items.sum(:net_pay_micros)
end
