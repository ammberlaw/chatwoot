# 知识库文档。对应 A-CRM(Twenty) knowledgeBase（CRM_SPEC §12.1）。
# 公司/个人两级：公司文档全员可读（销售员不可改附件的守卫在 S3 权限阶段落地）。
# == Schema Information
#
# Table name: crm_knowledge_docs
#
#  id         :bigint           not null, primary key
#  body       :text
#  category   :string
#  library    :string           default("SALES"), not null
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
#  index_crm_knowledge_docs_on_account_id_and_library   (account_id,library)
#  index_crm_knowledge_docs_on_account_id_and_scope     (account_id,scope)
#  index_crm_knowledge_docs_on_owner_id                 (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::KnowledgeDoc < ApplicationRecord
  SCOPES = %w[PERSONAL COMPANY].freeze
  # 资料库归属，与 scope（可见范围）正交：SALES=销售资料（CRM，邮件附件）；GENERAL=全公司知识（文档中心）。
  LIBRARIES = %w[SALES GENERAL].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  # 审计：记录文档的创建/编辑，供侧边栏「时间轴」展示。
  audited except: %i[created_at updated_at], on: %i[create update]

  has_many_attached :files

  validates :name, presence: true
  # 分类为账号级可管理的自由文本（见 Crm::KnowledgeCategory），不再硬校验枚举。
  validates :scope, inclusion: { in: SCOPES }
  validates :library, inclusion: { in: LIBRARIES }

  scope :company_docs, -> { where(scope: 'COMPANY') }
  scope :personal_of, ->(user_id) { where(scope: 'PERSONAL', owner_id: user_id) }
  scope :in_library, ->(library) { where(library: library) }
end
