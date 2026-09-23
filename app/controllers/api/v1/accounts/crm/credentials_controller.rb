# 文档中心「账号密码」。授权单元是分组：能看哪组由该组的 viewer_ids/manager_ids 决定，
# 管理员/副管理员直通全部。
#
# 两档：公司条目（挂分组、按分组名单授权、每次查看留痕）与个人条目（owner_id=本人，
# 创建人独占，管理员也看不到，不分组不留痕——自己看自己的密码记下来只会淹掉审计日志）。
#
# 关键约定：列表接口永远不下发密码明文，只给 has_password 标志；明文只走 reveal 单条接口，
# 公司条目每次都落一条查看记录。前端的「••••••」不是安全边界，接口层才是。
class Api::V1::Accounts::Crm::CredentialsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :set_credential, only: %i[update destroy reveal]
  # 可见 ≠ 可改：改/删还要过所在分组的维护权（reveal 只要可见）。
  before_action :ensure_writable, only: %i[update destroy]

  def index
    Crm::CredentialGroup.ensure_defaults!(Current.account) if manage_all?
    groups = visible_groups
    render json: {
      groups: groups.map { |g| group_json(g) },
      credentials: Current.account.crm_credentials.company
                          .where(crm_credential_group_id: groups.map(&:id))
                          .ordered.map { |c| credential_json(c) },
      # 个人条目只出自己的，与分组授权无关
      personal: Current.account.crm_credentials.personal_of(current_user.id)
                       .ordered.map { |c| credential_json(c) },
      can_manage_groups: manage_all?
    }
  end

  def create
    return create_personal if personal_param?

    group = writable_group(params.dig(:credential, :group_id))
    return render_forbidden if group.nil?

    position = (group.credentials.maximum(:position) || 0) + 1
    credential = group.credentials.create!(
      credential_params.merge(account_id: Current.account.id, position: position,
                              creator_id: current_user.id, updated_by_id: current_user.id)
    )
    render json: credential_json(credential)
  end

  def update
    return update_personal if @credential.personal?

    # 换组也要校验目标组的维护权，否则能把条目搬进自己维护不了的组。
    target = params.dig(:credential, :group_id).presence
    group = target ? writable_group(target) : @credential.group
    return render_forbidden if group.nil?

    attrs = credential_params
    # 密码留空 = 不改密码（编辑时前端不回填明文）。
    attrs = attrs.except(:password) if attrs[:password].blank?
    @credential.update!(attrs.merge(crm_credential_group_id: group.id, updated_by_id: current_user.id))
    render json: credential_json(@credential)
  end

  def destroy
    @credential.destroy!
    head :ok
  end

  # 取单条明文密码。公司条目记一条查看记录；个人条目是自己看自己的，不记。
  def reveal
    unless @credential.personal?
      action = Crm::CredentialView::ACTIONS.include?(params[:log_action]) ? params[:log_action] : 'reveal'
      Current.account.crm_credential_views.create!(
        crm_credential_id: @credential.id, user_id: current_user.id,
        action: action, created_at: Time.current
      )
    end
    render json: { password: @credential.password.to_s }
  end

  # 查看记录：管理员/副管理员看全部，其余只看自己有权限的分组。
  # 只含公司条目——个人条目压根不记（见 reveal）。
  def views
    rows = recent_views
    names = User.where(id: rows.map(&:user_id)).pluck(:id, :name).to_h
    titles = Current.account.crm_credentials.where(id: rows.map(&:crm_credential_id)).pluck(:id, :name).to_h
    render json: rows.map { |v|
      { id: v.id, user_name: names[v.user_id], credential_name: titles[v.crm_credential_id],
        action: v.action, created_at: v.created_at }
    }
  end

  private

  # 个人条目只有本人取得到（管理员也不行）；公司条目按分组可见范围收口。
  def set_credential
    company = Current.account.crm_credentials.company
    company = company.where(crm_credential_group_id: visible_groups.map(&:id)) unless manage_all?
    @credential = company.find_by(id: params[:id]) ||
                  Current.account.crm_credentials.personal_of(current_user.id).find_by(id: params[:id])
    render_forbidden if @credential.nil?
  end

  def ensure_writable
    return if @credential.personal? # 取到就是本人的（见 set_credential）

    render_forbidden if writable_group(@credential.crm_credential_group_id).nil?
  end

  def recent_views
    Current.account.crm_credential_views
           .joins('JOIN crm_credentials c ON c.id = crm_credential_views.crm_credential_id')
           .where(c: { crm_credential_group_id: visible_groups.map(&:id), owner_id: nil })
           .recent.limit(200)
  end

  # 前端建「我的账号」时传 scope=personal；不传分组也按个人处理，避免无归属的孤儿记录。
  def personal_param?
    params.dig(:credential, :scope).to_s == 'personal' || params.dig(:credential, :group_id).blank?
  end

  def create_personal
    scope = Current.account.crm_credentials.personal_of(current_user.id)
    credential = scope.create!(
      credential_params.merge(account_id: Current.account.id, owner_id: current_user.id,
                              crm_credential_group_id: nil,
                              position: (scope.maximum(:position) || 0) + 1,
                              creator_id: current_user.id, updated_by_id: current_user.id)
    )
    render json: credential_json(credential)
  end

  # 个人条目不能改归属、不能搬进分组——那等于把私人密码变成公司可见。
  def update_personal
    attrs = credential_params
    attrs = attrs.except(:password) if attrs[:password].blank?
    @credential.update!(attrs.merge(updated_by_id: current_user.id))
    render json: credential_json(@credential)
  end

  def credential_params
    params.require(:credential).permit(:name, :url, :username, :password, :note)
  end

  # 可见分组：管理员/副管全部；其余按 viewer_ids/manager_ids。viewer_ids 为空 = 不对外开放。
  def visible_groups
    @visible_groups ||= begin
      all = Current.account.crm_credential_groups.ordered.to_a
      manage_all? ? all : all.select { |g| g.viewer?(current_user.id) }
    end
  end

  # 可增删改该组条目：管理员/副管，或该组负责人。
  def writable_group(group_id)
    group = Current.account.crm_credential_groups.find_by(id: group_id)
    return nil if group.nil?

    group if manage_all? || group.manager?(current_user.id)
  end

  def group_json(group)
    {
      id: group.id, name: group.name, position: group.position,
      viewer_ids: group.viewer_ids, viewer_names: User.where(id: group.viewer_ids).pluck(:name),
      manager_ids: group.manager_ids, manager_names: User.where(id: group.manager_ids).pluck(:name),
      can_edit: manage_all? || group.manager?(current_user.id)
    }
  end

  # 注意：不含 password。明文只从 reveal 出。
  def credential_json(credential)
    {
      id: credential.id, group_id: credential.crm_credential_group_id,
      name: credential.name, url: credential.url, username: credential.username,
      note: credential.note, has_password: credential.password?,
      personal: credential.personal?,
      updated_at: credential.updated_at,
      updated_by: credential.updated_by&.crm_display_name
    }
  end

  def manage_all?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def render_forbidden
    render json: { error: '无权访问该账号分组' }, status: :forbidden
  end

  # 账号密码面向全公司（财务/人事也要用），不走 CRM 门禁；实际授权全靠分组名单。
  def ensure_crm_access
    true
  end

  # 控制器名推不出 Crm:: 下的模型，显式指定。
  def check_authorization
    authorize(Crm::Credential)
  end
end
