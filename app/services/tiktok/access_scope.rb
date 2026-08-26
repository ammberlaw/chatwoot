# TikTok 板块数据范围：给定账号内某成员，算出他能看/能改「哪些店铺」的数据。
# 口径：管理员/副管理员/财务看全部；部门负责人或成员看本部门店铺；其余无权。
# 财务只读（可见全部但 editable 为空）。返回 :all 或 shop_id 数组。
class Tiktok::AccessScope
  def initialize(account, account_user)
    @account = account
    @au = account_user
    @uid = account_user&.user_id
  end

  # 管理层+财务：看全部店铺数据。
  def all_access?
    @au&.administrator? || @au&.crm_deputy_admin? || @au&.crm_finance? || false
  end

  # 能否进入 TikTok 板块：管理层/财务，或任一 TK 部门的负责人/成员。
  def can_access?
    all_access? || own_department_ids.any?
  end

  # 能否管理部门/店铺归属（建部门、指派店铺）：仅管理员/副管理员。
  def can_manage?
    @au&.administrator? || @au&.crm_deputy_admin? || false
  end

  # 读范围：:all 或可见 shop_id 数组。
  def visible_shop_ids
    return :all if all_access?

    shop_ids_for(own_department_ids)
  end

  # 写范围：:all（管理员/副管）或本部门 shop_id 数组；财务只读返回 []。
  def editable_shop_ids
    return :all if @au&.administrator? || @au&.crm_deputy_admin?
    return [] if @au&.crm_finance?

    shop_ids_for(own_department_ids)
  end

  # 可见部门 id：管理层/财务看全部（:all），否则仅本人负责/在编的部门。
  # 供数据看板团队筛选下拉用（含未挂店铺的新部门）。
  def visible_department_ids
    return :all if all_access?

    own_department_ids
  end

  # 利润表可读：管理层/财务，或至少负责一个 TK 部门的负责人（普通成员不可见）。
  def can_view_profit?
    all_access? || led_department_ids.any?
  end

  # 利润表可见店铺：管理层/财务看全部；部门负责人看所负责部门的店铺；其余无。
  def profit_visible_shop_ids
    return :all if all_access?

    shop_ids_for(led_department_ids)
  end

  private

  # 该成员负责（leader）的 TK 部门 id。
  def led_department_ids
    @led_department_ids ||= @account.tiktok_departments.where(leader_id: @uid).pluck(:id)
  end

  # 该成员所属（负责/在编）的 TK 部门 id。
  def own_department_ids
    @own_department_ids ||= (led_department_ids + member_department_ids).uniq
  end

  def member_department_ids
    @au&.tiktok_department_id ? [@au.tiktok_department_id] : []
  end

  def shop_ids_for(dept_ids)
    return [] if dept_ids.empty?

    @account.tiktok_shops.where(department_id: dept_ids).pluck(:id)
  end
end
