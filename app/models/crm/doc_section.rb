# 文档中心资料板块。department_ids 为可见部门白名单（含其下级部门），空 = 全员可见。
# 默认 9 个板块随首次访问自动创建；可见性仅管理员可配置。
# == Schema Information
#
# Table name: crm_doc_sections
#
#  id             :bigint           not null, primary key
#  department_ids :bigint           default([]), not null, is an Array
#  name           :string           not null
#  position       :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
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

  def self.ensure_defaults!(account)
    DEFAULT_SECTIONS.each_with_index do |name, index|
      account.crm_doc_sections.find_or_create_by!(name: name) { |s| s.position = index }
    end
  end

  # 当前用户可见的板块 id：白名单为空全员可见；否则须属于白名单部门（含下级）。
  def self.visible_ids_for(account, user_id)
    user_dept_ids = account.org_memberships.where(user_id: user_id).pluck(:department_id)
    where(account_id: account.id).filter_map do |section|
      next section.id if section.department_ids.blank?

      allowed = Org::Department.subtree_ids(account, section.department_ids)
      section.id if allowed.intersect?(user_dept_ids)
    end
  end
end
