# TikTok 部门管理（团队式：负责人+成员）。建/改/删仅管理员/副管理员；
# 列表任何 TK 成员可读（供利润表/看板的部门筛选下拉用），按可见部门收口。
class Api::V1::Accounts::Tiktok::DepartmentsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :ensure_manage, except: %i[index]
  before_action :fetch_department, only: %i[update destroy]

  # 部门负责人/成员只看到自己负责或所属的部门；管理层/财务看全部。
  def index
    scope = Current.account.tiktok_departments.includes(:leader, :members, :shops)
    ids = tiktok_scope.visible_department_ids
    scope = scope.where(id: ids) unless ids == :all
    @departments = scope.order(:name)
  end

  def create
    @department = Current.account.tiktok_departments.create!(department_params)
    sync_members(@department)
    render :show
  end

  def update
    @department.update!(department_params)
    sync_members(@department)
    render :show
  end

  # 删除部门：成员归属与店铺归属经外键 on_delete nullify 自动释放。
  def destroy
    @department.destroy!
    head :ok
  end

  private

  def fetch_department
    @department = Current.account.tiktok_departments.find(params[:id])
  end

  def department_params
    params.require(:department).permit(:name, :leader_id)
  end

  # 成员集合：传入 member_ids（user_id 数组）→ 归本部门；移除本部门中不在列表里的旧成员。
  def sync_members(dept)
    return unless params[:department].key?(:member_ids)

    ids = Array(params[:department][:member_ids]).map(&:to_i)
    Current.account.account_users.where(tiktok_department_id: dept.id).where.not(user_id: ids)
           .update_all(tiktok_department_id: nil) # rubocop:disable Rails/SkipsModelValidations
    return if ids.empty?

    Current.account.account_users.where(user_id: ids)
           .update_all(tiktok_department_id: dept.id) # rubocop:disable Rails/SkipsModelValidations
  end
end
