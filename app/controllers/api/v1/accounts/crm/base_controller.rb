# CRM 所有控制器的基类：统一「能否进入 CRM」门禁 + 「按负责人的数据范围」助手。
# 门禁：系统管理员或被赋予 CRM 角色（主管/业务员）者可入；其他部门成员一律 403。
# 数据范围：见 Crm::AccessScope —— 管理员全部 / 主管团队 / 业务员本人。
class Api::V1::Accounts::Crm::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_crm_access

  private

  def ensure_crm_access
    return if Current.account_user&.can_access_crm?

    render json: { error: I18n.t('errors.crm.no_access', default: '无权访问 CRM') }, status: :forbidden
  end

  # 当前成员可见的负责人 id：:all 或 user_id 数组。
  def crm_visible_owner_ids
    @crm_visible_owner_ids ||=
      Crm::AccessScope.new(Current.account, Current.account_user).visible_owner_ids
  end

  # 按负责人列限定数据范围；:all 不加限制。默认列 owner_id（客户用 account_owner_id）。
  def scope_by_owner(relation, column: :owner_id)
    ids = crm_visible_owner_ids
    ids == :all ? relation : relation.where(column => ids)
  end
end
