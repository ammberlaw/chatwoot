# 跟进笔记。对应 A-CRM(Twenty) note 扩展（CRM_SPEC §3.4）。
# 建笔记自动刷新客户「上次跟进时间」——公海回收依据该字段（Twenty 需手动改，此处补齐语义）。
# == Schema Information
#
# Table name: crm_follow_up_notes
#
#  id                 :bigint           not null, primary key
#  body               :text
#  follow_up_method   :string
#  result_tag         :string
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  contact_id         :bigint
#  crm_customer_id    :bigint
#  crm_opportunity_id :bigint
#  owner_id           :bigint
#
# Indexes
#
#  index_crm_follow_up_notes_on_account_id          (account_id)
#  index_crm_follow_up_notes_on_contact_id          (contact_id)
#  index_crm_follow_up_notes_on_crm_customer_id     (crm_customer_id)
#  index_crm_follow_up_notes_on_crm_opportunity_id  (crm_opportunity_id)
#  index_crm_follow_up_notes_on_owner_id            (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_opportunity_id => crm_opportunities.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::FollowUpNote < ApplicationRecord
  FOLLOW_UP_METHODS = %w[EMAIL PHONE MEETING WHATSAPP WECHAT].freeze
  RESULT_TAGS = %w[INTERESTED WAITING_CUSTOMER WAITING_INTERNAL INVALID].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :owner, class_name: 'User', optional: true

  validates :title, presence: true
  validates :follow_up_method, inclusion: { in: FOLLOW_UP_METHODS }, allow_blank: true
  validates :result_tag, inclusion: { in: RESULT_TAGS }, allow_blank: true

  after_create :touch_customer_follow_up_at

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  private

  def touch_customer_follow_up_at
    crm_customer&.update_columns(last_follow_up_at: created_at)
  end
end
