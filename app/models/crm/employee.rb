# == Schema Information
#
# Table name: crm_employees
#
#  id                  :bigint           not null, primary key
#  bank_card_no        :string
#  bank_name           :string
#  birth_date          :date
#  contract_end_date   :date
#  contract_start_date :date
#  contract_type       :string
#  email               :string
#  employee_no         :string           not null
#  gender              :string
#  hire_date           :date
#  id_card_no          :string
#  job_category        :string
#  job_title           :string
#  name                :string           not null
#  native_place        :string
#  phone               :string
#  probation_months    :integer
#  regular_date        :date
#  renew_count         :integer
#  resign_date         :date
#  resign_reason       :text
#  resign_type         :string
#  salary_note         :string
#  status              :string           default("PROBATION"), not null
#  wechat              :string
#  work_location       :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  department_id       :bigint
#  user_id             :bigint
#
# Indexes
#
#  index_crm_employees_on_account_id                  (account_id)
#  index_crm_employees_on_account_id_and_employee_no  (account_id,employee_no) UNIQUE
#  index_crm_employees_on_account_id_and_status       (account_id,status)
#  index_crm_employees_on_account_id_and_user_id      (account_id,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#

# HR 员工主数据（员工档案）。状态：在职 / 试用 / 离职。
class Crm::Employee < ApplicationRecord
  belongs_to :account
  belongs_to :department, class_name: 'Org::Department', optional: true
  # 关联系统账号：离职交接（客户退公海/转移、文档归档、角色置无）依赖此关联。
  belongs_to :user, optional: true

  # 变更审计：谁在何时改了哪些字段（查看日志见 Crm::AccessLog）。
  audited

  has_one_attached :photo          # 证件照
  has_many_attached :entry_files   # 入职资料
  has_many_attached :resign_files  # 离职资料

  STATUSES = %w[ACTIVE PROBATION RESIGNED].freeze
  GENDERS = %w[MALE FEMALE].freeze
  CONTRACT_TYPES = %w[FIRST RENEWAL].freeze
  RESIGN_TYPES = %w[VOLUNTARY INVOLUNTARY].freeze

  validates :employee_no, presence: true, uniqueness: { scope: :account_id }
  validates :user_id, uniqueness: { scope: :account_id }, allow_nil: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :gender, inclusion: { in: GENDERS }, allow_blank: true
  validates :contract_type, inclusion: { in: CONTRACT_TYPES }, allow_blank: true
  validates :resign_type, inclusion: { in: RESIGN_TYPES }, allow_blank: true
end
