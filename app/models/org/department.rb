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

  def parent_not_self_or_descendant
    return if parent_id.blank?

    errors.add(:parent_id, '不能设为自己') if parent_id == id
    return if new_record?

    errors.add(:parent_id, '不能设为自己的下级') if self_and_descendant_ids.include?(parent_id)
  end
end
