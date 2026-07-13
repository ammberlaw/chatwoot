class Api::V1::Accounts::Org::DepartmentsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_department, only: [:update, :destroy]

  def index
    @departments = Current.account.org_departments.includes(:leader, :memberships).ordered
  end

  def create
    @department = Current.account.org_departments.create!(department_params)
  end

  def update
    @department.update!(department_params)
  end

  def destroy
    @department.destroy!
    head :ok
  end

  # 同级排序：positions 为有序的部门 id 数组，按序写回 position。
  def reorder
    Array(params[:positions]).each_with_index do |id, index|
      Current.account.org_departments.where(id: id).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  private

  def fetch_department
    @department = Current.account.org_departments.find(params[:id])
  end

  def check_authorization
    authorize(Org::Department)
  end

  def department_params
    params.require(:department).permit(:name, :parent_id, :leader_id, :position)
  end
end
