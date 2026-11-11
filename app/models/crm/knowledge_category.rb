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
#  parent_id  :bigint
#  section_id :bigint
#  user_id    :bigint
#
# Indexes
#
#  idx_crm_knowledge_cats_company_name           (account_id, COALESCE(section_id, (0)::bigint), COALESCE(parent_id, (0)::bigint), name) UNIQUE WHERE (user_id IS NULL)
#  idx_crm_knowledge_cats_personal_name          (account_id, user_id, COALESCE(parent_id, (0)::bigint), name) UNIQUE WHERE (user_id IS NOT NULL)
#  index_crm_knowledge_categories_on_account_id  (account_id)
#  index_crm_knowledge_categories_on_parent_id   (parent_id)
#  index_crm_knowledge_categories_on_section_id  (section_id)
#  index_crm_knowledge_categories_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::KnowledgeCategory < ApplicationRecord
  belongs_to :account
  belongs_to :discarded_by, class_name: 'User', optional: true
  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }
  # 空=公司分类（管理员/负责人维护）；非空=个人分类（本人自建自管）。
  belongs_to :user, optional: true
  # 自嵌套：parent 为空=板块下顶层分类；非空=子分类。支持任意层级（像电脑文件夹逐级下钻）。
  belongs_to :parent, class_name: 'Crm::KnowledgeCategory', optional: true
  has_many :children, class_name: 'Crm::KnowledgeCategory', foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  # 名字仅在「同一父文件夹内」唯一：不同父/不同层可重名（与 DB 唯一索引一致）。
  validates :name, presence: true
  validates :name, uniqueness: { scope: [:account_id, :user_id, :section_id, :parent_id], conditions: -> { kept } },
                   if: -> { discarded_at.nil? }

  validate :valid_parent, if: :will_save_change_to_parent_id?

  def valid_parent
    return if parent_id.nil?

    node = parent
    if !node || node.discarded_at || node.account_id != account_id || node.user_id != user_id || node.section_id != section_id
      errors.add(:parent_id, '目标文件夹与当前板块或归属不一致')
      return
    end
    seen = Set.new([id].compact)
    while node
      unless seen.add?(node.id)
        errors.add(:parent_id, '不能移动到自身或子文件夹')
        break
      end
      node = node.parent
    end
  end

  scope :ordered, -> { order(:position, :id) }
  scope :company_scope, -> { where(user_id: nil) }
  scope :personal_of, ->(user_id) { where(user_id: user_id) }
  # 公司分类按板块隔离：某板块（或聚合视图 section_id 为空）的分类列。
  scope :for_section, ->(section_id) { where(section_id: section_id) }
end
