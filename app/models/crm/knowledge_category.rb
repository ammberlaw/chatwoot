# 知识库文档分类：公司分类与个人分类两层，看板列与文档分类下拉均取自此表。
# == Schema Information
#
# Table name: crm_knowledge_categories
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  idx_crm_knowledge_cats_company_name           (account_id,name) UNIQUE WHERE (user_id IS NULL)
#  idx_crm_knowledge_cats_personal_name          (account_id,user_id,name) UNIQUE WHERE (user_id IS NOT NULL)
#  index_crm_knowledge_categories_on_account_id  (account_id)
#  index_crm_knowledge_categories_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::KnowledgeCategory < ApplicationRecord
  belongs_to :account
  # 空=公司分类（管理员/负责人维护）；非空=个人分类（本人自建自管）。
  belongs_to :user, optional: true

  validates :name, presence: true, uniqueness: { scope: [:account_id, :user_id] }

  scope :ordered, -> { order(:position, :id) }
  scope :company_scope, -> { where(user_id: nil) }
  scope :personal_of, ->(user_id) { where(user_id: user_id) }
end
