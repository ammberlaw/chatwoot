# 谁能审这张销售订单。
#
# 控制器（挡写）和 jbuilder（决定前端显不显示「通过/驳回」）都要问同一个问题，
# 所以收在这一处——两边各写一份的话，迟早出现「按钮看得见、点下去 403」。
#
# 口径：管理员/副管恒可审；其余要是**这张单业务员所在 CRM 团队的负责人**。
# 团队负责人自己建的单没有更上一级可批，落到管理员/副管手里——否则主管的单
# 会永远卡在待审核，他自己也转不了。
class Crm::SalesOrderApprover
  # order 为 nil 时问的是「这个人有没有审核身份」（建单时用来决定新单落不落待审核）。
  def self.can?(account_user, order = nil)
    return false unless account_user
    return true if account_user.administrator? || account_user.crm_deputy_admin?
    return false unless account_user.crm_team_lead?
    return true if order.nil?

    order.owner_id != account_user.user_id && team_owner_ids(account_user).include?(order.owner_id)
  end

  # 「分配给我审的单」——侧栏角标和工作台待办用这个，**不是** can?。
  #
  # can? 答的是「能不能点通过」：管理员/副管对任何一张都能点，那是代办能力。
  # 待办答的是「这张派给了谁」，口径必须与 notify_ids（真正发通知给谁）一致：
  # 先找业务员所在团队的负责人，没负责人、或负责人就是他本人（自己的单自己审不了）
  # 才落到管理员/副管。
  #
  # 两者混用的后果：副管的待办和角标里躺着全公司每一张待审单。2026-10-27 生产实查
  # 5 张待审，其中 3 张该团队负责人审，只有 2 张真该落到管理员/副管——多出来的 3 张
  # 是别人团队的事。手机推送没这问题（走的是 notify_ids），于是角标和推送还对不上。
  # 用户原话：「不是自己的订单，不应进入自己的待办」。
  #
  # 可查看范围不受影响：列表页的 approval=PENDING 是普通列筛选，管理员照样翻得到全部。
  def self.pending_scope(account, account_user)
    scope = account.crm_sales_orders.where(approval_status: 'PENDING')
    return scope.none unless account_user

    owner_ids = led_owner_ids(account, account_user.user_id)
    owner_ids |= admin_fallback_owner_ids(account) if account_user.administrator? || account_user.crm_deputy_admin?
    return scope.none if owner_ids.empty?

    scope.where(owner_id: owner_ids)
  end

  # 我担任负责人的团队里，除我之外的成员（自己的单自己审不了）。
  def self.led_owner_ids(account, user_id)
    team_ids = account.crm_teams.where(team_lead_id: user_id).pluck(:id)
    return [] if team_ids.empty?

    account.account_users.where(crm_team_id: team_ids).where.not(user_id: user_id).pluck(:user_id)
  end
  private_class_method :led_owner_ids

  # 审批真正落到管理员/副管头上的那些业务员：没带团队、团队没设负责人、
  # 或负责人就是他自己。这是 notify_ids 第 38 行那条兜底的反查，两边必须同口径。
  def self.admin_fallback_owner_ids(account)
    leads = account.crm_teams.pluck(:id, :team_lead_id).to_h
    account.account_users.pluck(:user_id, :crm_team_id).filter_map do |uid, team_id|
      lead = team_id.present? ? leads[team_id] : nil
      uid if lead.blank? || lead == uid
    end
  end
  private_class_method :admin_fallback_owner_ids

  # 这张单该提醒谁去审。优先该业务员所在团队的负责人；团队没设负责人、或负责人
  # 就是业务员本人（审不了自己的单）时落到管理员/副管——不然单子挂在那儿没人知道，
  # 只能等业务员开口问。
  def self.notify_ids(account, order)
    lead_id = team_lead_id_for(account, order.owner_id)
    return [lead_id] if lead_id.present? && lead_id != order.owner_id

    admin_like_ids(account)
  end

  def self.team_owner_ids(account_user)
    ids = Crm::AccessScope.new(account_user.account, account_user).team_visible_owner_ids
    ids == :all ? [] : ids
  end
  private_class_method :team_owner_ids

  # 业务员所在 CRM 团队的负责人（团队归属存在 account_users.crm_team_id）。
  def self.team_lead_id_for(account, owner_id)
    return nil if owner_id.blank?

    team_id = account.account_users.where(user_id: owner_id).pick(:crm_team_id)
    return nil if team_id.blank?

    account.crm_teams.where(id: team_id).pick(:team_lead_id)
  end
  private_class_method :team_lead_id_for

  def self.admin_like_ids(account)
    account.account_users
           .where(role: :administrator)
           .or(account.account_users.where(crm_role: 'deputy_admin'))
           .pluck(:user_id)
  end
  private_class_method :admin_like_ids
end
