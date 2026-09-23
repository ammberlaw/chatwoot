# 账号密码分组的增删改 + 配置可见成员/负责人。仅管理员/副管理员。
class Api::V1::Accounts::Crm::CredentialGroupsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def create
    name = params.dig(:group, :name).to_s.strip
    return render json: { error: '分组名称不能为空' }, status: :unprocessable_entity if name.blank?

    position = (Current.account.crm_credential_groups.maximum(:position) || 0) + 1
    group = Current.account.crm_credential_groups.create!(name: name, position: position)
    render json: group_json(group)
  end

  def update
    group = Current.account.crm_credential_groups.find(params[:id])
    updates = member_updates
    if params[:group].key?(:name)
      name = params[:group][:name].to_s.strip
      return render json: { error: '分组名称不能为空' }, status: :unprocessable_entity if name.blank?

      updates[:name] = name
    end
    group.update!(updates)
    render json: group_json(group)
  end

  # 删组连同组内账号一起删（外键 on_delete: :cascade），前端须二次确认。
  def destroy
    Current.account.crm_credential_groups.find(params[:id]).destroy!
    head :ok
  end

  private

  def member_updates
    updates = {}
    updates[:viewer_ids] = sanitized_member_ids(:viewer_ids) if params[:group].key?(:viewer_ids)
    updates[:manager_ids] = sanitized_member_ids(:manager_ids) if params[:group].key?(:manager_ids)
    updates
  end

  def sanitized_member_ids(key)
    ids = Array(params.dig(:group, key)).map(&:to_i).uniq
    Current.account.account_users.where(user_id: ids).pluck(:user_id)
  end

  def group_json(group)
    {
      id: group.id, name: group.name, position: group.position,
      viewer_ids: group.viewer_ids, viewer_names: User.where(id: group.viewer_ids).pluck(:name),
      manager_ids: group.manager_ids, manager_names: User.where(id: group.manager_ids).pluck(:name),
      can_edit: true
    }
  end

  def ensure_crm_access
    true
  end

  def check_authorization
    authorize(Crm::CredentialGroup)
  end
end
