class Api::V1::Accounts::Org::DepartmentsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_department, only: [:update, :destroy, :impact]

  def index
    @departments = Current.account.org_departments.includes(:leader, :memberships).ordered
    @departments = @departments.active unless params[:include_archived] == 'true' && Current.account_user.org_maintainer?
  end

  def create
    Current.account.with_lock(requires_new: true) { @department = Current.account.org_departments.create!(department_params) }
  end

  def update
    Current.account.with_lock(requires_new: true) { @department.lock!; @department.update!(department_params) }
  end

  def destroy
    archived = false
    Current.account.with_lock(requires_new: true) { @department.lock!; archived = @department.archive_or_destroy! }
    render json: { archived: archived }
  end

  # 同级排序：positions 为有序的部门 id 数组，按序写回 position。
  def reorder
    Array(params[:positions]).each_with_index do |id, index|
      Current.account.org_departments.where(id: id).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  def impact
    render json: @department.impact
  end

  def history
    rows = Crm::HrEvent.where(account: Current.account).where("kind LIKE 'org_%'").includes(:actor).order(id: :desc).limit(100)
    rows = rows.where(department_id: params[:department_id]) if params[:department_id].present?
    render json: { payload: rows.map { |event| { id: event.id, kind: event.kind, payload: event.payload,
      actor_name: event.actor&.crm_display_name || '系统', created_at: event.created_at } } }
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
