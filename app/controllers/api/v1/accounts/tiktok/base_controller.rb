# TikTok 板块基类：门禁 + 按部门/店铺的数据范围。
# 可入：管理员/副管理员/财务，或任一 TK 部门的负责人/成员（见 Tiktok::AccessScope）。
class Api::V1::Accounts::Tiktok::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_tiktok_access

  private

  def tiktok_scope
    @tiktok_scope ||= Tiktok::AccessScope.new(Current.account, Current.account_user)
  end

  def ensure_tiktok_access
    return if tiktok_scope.can_access?

    render json: { error: I18n.t('errors.tiktok.no_access', default: '无权访问 TikTok 板块') }, status: :forbidden
  end

  # 管理动作（建部门/指派店铺）仅管理员/副管理员。
  def ensure_manage
    return if tiktok_scope.can_manage?

    render json: { error: '仅管理员/副管理员可管理' }, status: :forbidden
  end

  # 按可见店铺收口（relation 需含 shop_id 列）。:all 不加限制。
  def scope_visible(relation)
    ids = tiktok_scope.visible_shop_ids
    ids == :all ? relation : relation.where(shop_id: ids)
  end

  # 写权限：该 shop 是否在可编辑范围（财务只读、别的部门不可改）。
  def ensure_editable_shop!(shop_id)
    ids = tiktok_scope.editable_shop_ids
    return if ids == :all
    return if ids.include?(shop_id.to_i)

    render json: { error: '无权修改该店铺数据' }, status: :forbidden
  end
end
