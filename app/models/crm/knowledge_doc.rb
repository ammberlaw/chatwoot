# 知识库文档。对应 A-CRM(Twenty) knowledgeBase（CRM_SPEC §12.1）。
# 公司/个人两级：公司文档全员可读（销售员不可改附件的守卫在 S3 权限阶段落地）。
# == Schema Information
#
# Table name: crm_knowledge_docs
#
#  id         :bigint           not null, primary key
#  body       :text
#  category   :string
#  name       :string           not null
#  scope      :string           default("PERSONAL"), not null
#  summary    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint
#
# Indexes
#
#  index_crm_knowledge_docs_on_account_id               (account_id)
#  index_crm_knowledge_docs_on_account_id_and_category  (account_id,category)
#  index_crm_knowledge_docs_on_account_id_and_scope     (account_id,scope)
#  index_crm_knowledge_docs_on_owner_id                 (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::KnowledgeDoc < ApplicationRecord
  CATEGORIES = %w[PRODUCT_CATALOG FAQ AFTER_SALES QUOTE_TEMPLATE COMPANY_CERT USER_MANUAL PRODUCT_SPEC PAYMENT_ACCOUNT].freeze
  SCOPES = %w[PERSONAL COMPANY].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  has_many_attached :files

  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :scope, inclusion: { in: SCOPES }

  scope :company_docs, -> { where(scope: 'COMPANY') }
  scope :personal_of, ->(user_id) { where(scope: 'PERSONAL', owner_id: user_id) }
end
