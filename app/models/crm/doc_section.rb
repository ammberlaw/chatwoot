# 文档中心资料板块。viewer_ids 为可见成员白名单，空 = 全员可见（如人事/财务资料只给两三个人看）。
# 默认 9 个板块随首次访问自动创建；可见性仅管理员可配置。
# == Schema Information
#
# Table name: crm_doc_sections
#
#  id          :bigint           not null, primary key
#  manager_ids :bigint           default([]), not null, is an Array
#  name        :string           not null
#  position    :integer          default(0), not null
#  viewer_ids  :bigint           default([]), not null, is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_crm_doc_sections_on_account_id           (account_id)
#  index_crm_doc_sections_on_account_id_and_name  (account_id,name) UNIQUE
#
class Crm::DocSection < ApplicationRecord
  DEFAULT_SECTIONS = %w[销售资料 公司制度 流程 培训资料 单证与报关资料 人事资料 财务资料 采购与供应商资料 生产管理资料].freeze

  belongs_to :account
  has_many :knowledge_docs, class_name: 'Crm::KnowledgeDoc', foreign_key: :section_id,
                            inverse_of: :section, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }

  # 板块负责人（可多人）：可编辑/删除该板块下所有公司文档。
  def manager?(user_id)
    manager_ids.include?(user_id)
  end

  def managers
    User.where(id: manager_ids)
  end

  # 该用户负责的板块 id（用于文档管理权判断，一次性查库）。
  def self.managed_ids_for(account, user_id)
    where(account_id: account.id).where('? = ANY(manager_ids)', user_id).pluck(:id)
  end

  def self.ensure_defaults!(account)
    DEFAULT_SECTIONS.each_with_index do |name, index|
      account.crm_doc_sections.find_or_create_by!(name: name) { |s| s.position = index }
    end
  end

  # 可见成员（可多人）：白名单为空则全员可见。
  def viewer?(user_id)
    viewer_ids.blank? || viewer_ids.include?(user_id)
  end

  def viewers
    User.where(id: viewer_ids)
  end

  # 当前用户可见的板块 id：可见成员白名单为空=全员可见；否则须在名单内。
  def self.visible_ids_for(account, user_id)
    where(account_id: account.id).filter_map do |section|
      section.id if section.viewer?(user_id)
    end
  end
end
