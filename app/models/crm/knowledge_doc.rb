# 知识库文档。对应 A-CRM(Twenty) knowledgeBase（CRM_SPEC §12.1）。
# 公司/个人两级：公司文档全员可读（销售员不可改附件的守卫在 S3 权限阶段落地）。
# == Schema Information
#
# Table name: crm_knowledge_docs
#
#  id              :bigint           not null, primary key
#  body            :text
#  category        :string
#  discarded_at    :datetime
#  library         :string           default("SALES"), not null
#  manager_ids     :bigint           default([]), not null, is an Array
#  name            :string           not null
#  scope           :string           default("PERSONAL"), not null
#  summary         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  discarded_by_id :bigint
#  owner_id        :bigint
#  section_id      :bigint
#
# Indexes
#
#  index_crm_knowledge_docs_on_account_id                   (account_id)
#  index_crm_knowledge_docs_on_account_id_and_category      (account_id,category)
#  index_crm_knowledge_docs_on_account_id_and_discarded_at  (account_id,discarded_at)
#  index_crm_knowledge_docs_on_account_id_and_library       (account_id,library)
#  index_crm_knowledge_docs_on_account_id_and_scope         (account_id,scope)
#  index_crm_knowledge_docs_on_account_id_and_section_id    (account_id,section_id)
#  index_crm_knowledge_docs_on_owner_id                     (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (section_id => crm_doc_sections.id) ON DELETE => nullify
#
class Crm::KnowledgeDoc < ApplicationRecord
  SCOPES = %w[PERSONAL COMPANY].freeze
  # 资料库归属，与 scope（可见范围）正交：SALES=销售资料（CRM，邮件附件）；GENERAL=全公司知识（文档中心）。
  LIBRARIES = %w[SALES GENERAL].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  # 文档中心资料板块（GENERAL 库使用）；板块可按部门配置可见性。
  belongs_to :section, class_name: 'Crm::DocSection', optional: true
  belongs_to :discarded_by, class_name: 'User', optional: true

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
  # 软删除（文档回收站）：删除的文档进回收站，仅管理员可查看/恢复/彻底删除。
  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  def discard!(user_id)
    update!(discarded_at: Time.current, discarded_by_id: user_id)
  end

  def restore!
    update!(discarded_at: nil, discarded_by_id: nil)
  end
end
