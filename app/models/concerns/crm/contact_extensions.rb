# A-CRM person 扩展：挂在 Chatwoot Contact 上的外贸联系人字段与客户关联。
# 字段清单见 CRM_SPEC §3.2；国家/客户分组/联系偏好选项与 Crm::Customer 保持同一套常量。
module Crm::ContactExtensions
  extend ActiveSupport::Concern

  # 商显与工控已合并为「商显工控」（COMMERCIAL_DISPLAY）。
  PRODUCT_CATEGORIES = %w[TABLET COMMERCIAL_DISPLAY].freeze

  included do
    belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true

    validates :contact_preference, inclusion: { in: Crm::Customer::CONTACT_PREFERENCES }, allow_blank: true
    validates :product_category, inclusion: { in: PRODUCT_CATEGORIES }, allow_blank: true
    validates :country_region, inclusion: { in: Crm::Customer::COUNTRIES }, allow_blank: true
    validates :customer_group, inclusion: { in: Crm::Customer::CUSTOMER_GROUPS }, allow_blank: true
    validate :crm_customer_belongs_to_same_account

    scope :primary_contacts, -> { where(is_primary_contact: true) }
  end

  private

  def crm_customer_belongs_to_same_account
    return if crm_customer_id.blank? || crm_customer.blank?
    return if crm_customer.account_id == account_id

    errors.add(:crm_customer_id, 'must belong to the same account')
  end
end
