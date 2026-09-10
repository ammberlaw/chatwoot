# 岗位权限模板管理：管理员自定义「岗位 = 系统角色 + 模块 + MES 岗位 + 财务」，供成员权限页一键套用。
# 仅超级管理员 / 副管理员可管理（与成员角色任免同一权限级别）。
class Api::V1::Accounts::Crm::RoleTemplatesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin
  before_action :fetch_template, only: %i[update destroy]

  # 首次访问且账号还没有模板时，播种一套常用岗位当起点（管理员之后可任意改删）。
  def index
    Crm::RoleTemplate.seed_defaults!(Current.account)
    @templates = Current.account.crm_role_templates.ordered
  end

  def create
    @template = Current.account.crm_role_templates.create!(template_params.merge(position: next_position))
    render :show
  end

  def update
    @template.update!(template_params)
    render :show
  end

  def destroy
    @template.destroy!
    head :ok
  end

  private

  def fetch_template
    @template = Current.account.crm_role_templates.find(params[:id])
  end

  def ensure_admin
    return if Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?

    render json: { error: '仅超级管理员或管理员可管理岗位模板' }, status: :forbidden
  end

  def next_position
    (Current.account.crm_role_templates.maximum(:position) || -1) + 1
  end

  def template_params
    params.require(:role_template)
          .permit(:name, :system_role, :crm_finance, module_access: [], mes_roles: [])
  end
end
