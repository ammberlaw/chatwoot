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
  has_many :children, class_name: 'Org::Department', foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error
  has_many :memberships, class_name: 'Org::Membership', dependent: :restrict_with_error
  has_many :members, through: :memberships, source: :user

  validates :name, presence: true
  validate :parent_not_self_or_descendant

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :roots, -> { where(parent_id: nil) }

  validate :valid_account_links
  before_destroy :protect_business_history, prepend: true
  after_save :sync_roles_and_history
  after_destroy { Org::ManagedRoleSync.perform(account) }

  def active? = archived_at.nil?

  def active_member_count
    memberships.where(user_id: account.account_users.active_members.select(:user_id)).count
  end

  def impact
    { children: children.active.count, members: active_member_count,
      employees: account.crm_employees.where(department_id: id).where.not(status: 'RESIGNED').count,
      leader: leader_id.present?, history: business_history? }
  end

  def business_history?
    account.crm_employees.exists?(department_id: id) || account.oa_approval_requests.exists?(department_id: id) ||
      account.crm_petty_cash_books.exists?(org_department_id: id) || Erp::VoucherLine.where(account_id: account_id, department_id: id).exists? ||
      Erp::FixedAsset.where(account_id: account_id, department_id: id).exists? || account.crm_member_invites.exists?(department_id: id)
  end

  def archive_or_destroy!
    dependencies = impact
    if dependencies[:children].positive? || dependencies[:members].positive? || dependencies[:employees].positive? || dependencies[:leader]
      errors.add(:base, '请先迁移在职成员、员工档案、下级部门并移交负责人')
      raise ActiveRecord::RecordInvalid, self
    end
    if business_history? || children.exists? || memberships.exists?
      update!(archived_at: Time.current)
      true
    else
      destroy!
      false
    end
  end

  BUSINESS_KEYWORDS = %w[销售 业务].freeze

  # 业务条线部门：自身或任一上级部门名称含「销售/业务」。
  def business_line?
    node = self
    seen = []
    while node && seen.exclude?(node.id)
      seen << node.id
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

  # 某成员的直属主管们 user_id：成员可能属于多个部门，各部门分别向上找最近一个
  # 有 leader（且非本人）的部门的 leader，去重返回（提交考核/提成后通知这些人去审）。
  def self.managers_of(account, user_id)
    account.org_memberships.where(user_id: user_id).pluck(:department_id)
           .filter_map { |dept_id| nearest_leader(account, dept_id, user_id) }.uniq
  end

  # 从某部门向上找最近一个有 leader（且非本人）的部门的 leader；无则 nil。
  def self.nearest_leader(account, dept_id, user_id)
    seen = []
    while dept_id && seen.exclude?(dept_id)
      seen << dept_id
      dept = account.org_departments.find_by(id: dept_id)
      return nil unless dept
      return dept.leader_id if dept.active? && dept.leader_id != user_id && account.account_users.active_members.exists?(user_id: dept.leader_id)

      dept_id = dept.parent_id
    end
    nil
  end

  private

  def valid_account_links
    if archived_at_in_database.present? && (changes.keys & %w[name parent_id leader_id archived_at]).any?
      errors.add(:base, '已停用部门只保留历史，不能修改')
    end
    if parent_id.present? && !account.org_departments.active.exists?(id: parent_id)
      errors.add(:parent_id, '上级部门不存在、已停用或不属于当前公司')
    end
    if leader_id.present? && !account.account_users.active_members.exists?(user_id: leader_id)
      errors.add(:leader_id, '负责人必须是当前公司在职成员')
    end
    if archived_at.present? && new_record?
      errors.add(:base, '新部门不能直接归档')
    end
  end

  def protect_business_history
    return unless business_history?

    errors.add(:base, '部门已有业务记录，请归档并保留历史')
    throw :abort
  end

  def sync_roles_and_history
    return unless (saved_changes.keys & %w[id name parent_id leader_id archived_at]).any?

    Org::ManagedRoleSync.perform(account)
    Crm::HrEvent.record!(account: account, department: self, kind: 'org_department_changed',
                        payload: { department_name: name, changes: saved_changes.slice('name', 'parent_id', 'leader_id', 'archived_at') })
  end

  def parent_not_self_or_descendant
    return if parent_id.blank?

    errors.add(:parent_id, '不能设为自己') if parent_id == id
    return if new_record?

    errors.add(:parent_id, '不能设为自己的下级') if self_and_descendant_ids.include?(parent_id)
  end
end
