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

  validates :probation_months, :renew_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :valid_dates_and_links

  private

  def valid_dates_and_links
    %w[birth_date hire_date regular_date contract_start_date contract_end_date resign_date].each do |field|
      raw = public_send("#{field}_before_type_cast")
      next if raw.blank? || raw.is_a?(Date) || raw.is_a?(Time)
      begin
        raise ArgumentError unless raw.is_a?(String) && raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        Date.iso8601(raw)
      rescue ArgumentError
        errors.add(field, '日期格式不正确')
      end
    end
    if department_id.present? && (new_record? || will_save_change_to_department_id?)
      errors.add(:department_id, '部门不存在、已停用或不属于当前公司') unless account.org_departments.active.exists?(id: department_id)
    end
    if user_id.present?
      member = account.account_users.find_by(user_id: user_id)
      errors.add(:user_id, '账号不属于当前公司') unless member
      if member && status != 'RESIGNED' && member.deactivated_at.present?
        errors.add(:user_id, '请先在成员管理中恢复该账号')
      elsif member && status == 'RESIGNED' && member.deactivated_at.nil? && (new_record? || will_save_change_to_status?)
        errors.add(:status, '关联在职账号必须通过离职交接办理')
      end
    end
    [[hire_date, regular_date, :regular_date], [contract_start_date, contract_end_date, :contract_end_date],
     [hire_date, resign_date, :resign_date]].each do |first, last, key|
      errors.add(key, '结束日期不能早于开始日期') if first && last && first > last
    end
    errors.add(:birth_date, '出生日期不能晚于今天') if birth_date && birth_date > Date.current
  end

  public

  # 指定月份（考核月）该员工是否处于试用期。绩效核算据此判断是否发绩效薪资。
  # 优先按转正日期；无转正日期时按「入职日 + 试用期月数」推算；再兜底看当前状态。
  def probation_in?(month)
    end_date = probation_end_date
    return status == 'PROBATION' unless end_date

    month.to_date.beginning_of_month < end_date.beginning_of_month
  end

  # 试用期结束日：转正日期优先，否则入职日 + 试用期月数；都缺则无法推算。
  def probation_end_date
    return regular_date if regular_date
    return hire_date + probation_months.months if hire_date && probation_months

    nil
  end
end
