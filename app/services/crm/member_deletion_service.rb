# 彻底删除成员账号：只用于清理建错 / 测试 / 重复的账号。不可恢复。
# 前置：必须已「离职」——离职流程已把名下客户/商机交接、个人文档进回收站；此处只清个人残留数据再删 User。
# 超级管理员账号不可删。业务级权限校验在控制器 destroy_error。
#
# 为什么要手动清这几张表：它们 user 外键 NOT NULL 且无 DB 外键约束，User.destroy 不会级联也不会被挡，
# 直接删会留下孤儿行。其余 crm_/mes_ 表都是 on_delete: :nullify 外键、Chatwoot 核心表都有 dependent，自理。
class Crm::MemberDeletionService
  class NotDeletable < StandardError; end

  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
    @user = account_user.user
  end

  def perform
    raise NotDeletable, '请先在成员管理里办理「离职」交接，再彻底删除' if @account_user.deactivated_at.blank?
    raise NotDeletable, '不能删除超级管理员账号' if @account_user.administrator?

    ActiveRecord::Base.transaction do
      # 先同步删成员关系：立即从成员列表消失，并触发 Chatwoot 的 agent 清理（收件箱/团队/会话）。
      @account_user.destroy!
      nullify_residual_ownership
      purge_personal_records
      @user.destroy!
    end
  end

  private

  # 兜底：离职已交接当前客户/商机，这里把仍指向该用户的所有权引用置空，避免留死指针。
  def nullify_residual_ownership
    @account.crm_customers.where(account_owner_id: @user.id).update_all(account_owner_id: nil) # rubocop:disable Rails/SkipsModelValidations
    @account.crm_customers.where(previous_owner_id: @user.id).update_all(previous_owner_id: nil) # rubocop:disable Rails/SkipsModelValidations
    @account.crm_customers.where(assigned_by_id: @user.id).update_all(assigned_by_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  # 个人数据(NOT NULL 无 nullify 外键)：删前清掉。日程用 destroy_all 以级联其参与人。
  def purge_personal_records
    uid = @user.id
    @account.crm_schedule_events.where(owner_id: uid).destroy_all
    Crm::ScheduleParticipant.where(user_id: uid).delete_all
    Crm::EmailFolder.where(owner_id: uid).delete_all
    Crm::QuickText.where(owner_id: uid).delete_all
    Crm::CustomerFavorite.where(user_id: uid).delete_all
    Crm::AccessLog.where(user_id: uid).delete_all
    Crm::AttendanceRecord.where(user_id: uid).delete_all
    Crm::EmailDistribution.where(from_user_id: uid).or(Crm::EmailDistribution.where(to_user_id: uid)).delete_all
    Org::Membership.where(user_id: uid).delete_all
  end
end
