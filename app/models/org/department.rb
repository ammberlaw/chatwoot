# 组织架构部门（自引用树）。公司组织结构的节点，成员经 Org::Membership 挂到部门。
# 与 Crm::Team（扁平销售团队）并存，互不影响。
# == Schema Information
#
# Table name: org_departments
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  leader_id  :bigint
#  parent_id  :bigint
#
# Indexes
#
#  index_org_departments_on_account_id                (account_id)
#  index_org_departments_on_account_id_and_parent_id  (account_id,parent_id)
#  index_org_departments_on_leader_id                 (leader_id)
#
class Org::Department < ApplicationRecord
  belongs_to :account
  belongs_to :parent, class_name: 'Org::Department', optional: true
  belongs_to :leader, class_name: 'User', optional: true
  has_many :children, class_name: 'Org::Department', foreign_key: :parent_id, inverse_of: :parent, dependent: :destroy
  has_many :memberships, class_name: 'Org::Membership', dependent: :destroy
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true
  validate :parent_not_self_or_descendant

  scope :ordered, -> { order(:position, :id) }
  scope :roots, -> { where(parent_id: nil) }

  after_destroy :demote_former_leader
  # 组织架构与系统角色联动（仅业务条线部门）：设为业务部门负责人自动升为「部门负责人」角色；
  # 卸任且不再负责任何业务部门时回落为「业务员」。非业务部门（生产/人事等）的负责人不联动，
  # 不会因此获得 CRM 入口。超级管理员/管理员不受影响。
  after_save :sync_leader_crm_role, if: :saved_change_to_leader_id?

  BUSINESS_KEYWORDS = %w[销售 业务].freeze

  # 业务条线部门：自身或任一上级部门名称含「销售/业务」。
  def business_line?
    node = self
    while node
      return true if BUSINESS_KEYWORDS.any? { |keyword| node.name.include?(keyword) }

      node = node.parent_id && account.org_departments.find_by(id: node.parent_id)
    end
    false
  end

  # 后代 id（含自身），用于「按部门授权」时圈定范围，以及防止环形父级。
  def self_and_descendant_ids
    self.class.subtree_ids(account, [id])
  end

  # 给定一组部门 id，返回它们及其所有下级部门 id（含自身），账号内 BFS 展开。
  def self.subtree_ids(account, root_ids)
    ids = Array(root_ids).map(&:to_i).uniq
    frontier = ids
    until frontier.empty?
      children = account.org_departments.where(parent_id: frontier).pluck(:id)
      fresh = children - ids
      ids.concat(fresh)
      frontier = fresh
    end
    ids
  end

  private

  def sync_leader_crm_role
    old_id, new_id = saved_change_to_leader_id
    promote_to_manager(new_id)
    demote_if_not_leading(old_id)
  end

  def demote_former_leader
    demote_if_not_leading(leader_id)
  end

  def promote_to_manager(user_id)
    return if user_id.blank?
    return unless business_line?

    au = account.account_users.find_by(user_id: user_id)
    return unless au && !au.administrator? && ['sales', nil].include?(au.crm_role)

    au.update!(crm_role: 'manager')
  end

  def demote_if_not_leading(user_id)
    return if user_id.blank?
    return if account.org_departments.where(leader_id: user_id).any?(&:business_line?)

    au = account.account_users.find_by(user_id: user_id)
    au.update!(crm_role: 'sales') if au&.crm_role == 'manager'
  end

  def parent_not_self_or_descendant
    return if parent_id.blank?

    errors.add(:parent_id, '不能设为自己') if parent_id == id
    return if new_record?

    errors.add(:parent_id, '不能设为自己的下级') if self_and_descendant_ids.include?(parent_id)
  end
end
