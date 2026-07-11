class Api::V1::Accounts::Crm::FollowUpTasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_task, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 25

  def index
    @tasks_scope = filtered_tasks
    @tasks_count = @tasks_scope.count
    @tasks = @tasks_scope.order(Arel.sql('due_at ASC NULLS LAST')).page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @task = Current.account.crm_follow_up_tasks.create!(task_params.merge(assignee_id: task_params[:assignee_id] || current_user.id))
  end

  def update
    @task.update!(task_params)
  end

  def destroy
    @task.destroy!
    head :ok
  end

  private

  def fetch_task
    @task = Current.account.crm_follow_up_tasks.find(params[:id])
  end

  def check_authorization
    authorize(Crm::FollowUpTask)
  end

  # 待办跟进视图：open（未完成）、我的、按客户、按类型。
  def filtered_tasks
    scope = Current.account.crm_follow_up_tasks
    scope = scope.open_tasks if params[:filter] == 'open'
    scope = scope.assigned_to(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.where(task_type: params[:task_type]) if params[:task_type].present?
    scope
  end

  def task_params
    params.require(:task).permit(:title, :body, :status, :due_at, :task_type, :related_business_code,
                                 :crm_customer_id, :contact_id, :crm_opportunity_id, :assignee_id)
  end
end
