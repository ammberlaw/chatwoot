# 跟进任务。对应 A-CRM(Twenty) task 扩展（CRM_SPEC §3.5）。
# == Schema Information
#
# Table name: crm_follow_up_tasks
#
#  id                    :bigint           not null, primary key
#  body                  :text
#  due_at                :datetime
#  related_business_code :string
#  status                :string           default("TODO"), not null
#  task_type             :string
#  title                 :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  assignee_id           :bigint
#  contact_id            :bigint
#  crm_customer_id       :bigint
#  crm_opportunity_id    :bigint
#
# Indexes
#
#  index_crm_follow_up_tasks_on_account_id             (account_id)
#  index_crm_follow_up_tasks_on_account_id_and_due_at  (account_id,due_at)
#  index_crm_follow_up_tasks_on_account_id_and_status  (account_id,status)
#  index_crm_follow_up_tasks_on_assignee_id            (assignee_id)
#  index_crm_follow_up_tasks_on_contact_id             (contact_id)
#  index_crm_follow_up_tasks_on_crm_customer_id        (crm_customer_id)
#  index_crm_follow_up_tasks_on_crm_opportunity_id     (crm_opportunity_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id) ON DELETE => nullify
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_opportunity_id => crm_opportunities.id) ON DELETE => nullify
#
class Crm::FollowUpTask < ApplicationRecord
  STATUSES = %w[TODO IN_PROGRESS DONE].freeze
  TASK_TYPES = %w[CUSTOMER_FOLLOW_UP EMAIL_REPLY QUOTE_APPROVAL ORDER_FOLLOW_UP SHIPMENT_FOLLOW_UP PAYMENT_REMINDER].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :task_type, inclusion: { in: TASK_TYPES }, allow_blank: true

  scope :open_tasks, -> { where.not(status: 'DONE') }
  scope :assigned_to, ->(user_id) { where(assignee_id: user_id) }
end
