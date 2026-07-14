class Api::V1::Accounts::Crm::SalesTargetsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_target, only: [:show, :update, :destroy]

  def index
    @targets_scope = filtered_targets
    @targets = @targets_scope.order(target_month: :desc)
  end

  def show; end

  def create
    @target = Current.account.crm_sales_targets.create!(target_params.merge(owner_id: target_params[:owner_id] || current_user.id))
  end

  def update
    @target.update!(target_params)
  end

  def destroy
    @target.destroy!
    head :ok
  end

  private

  def fetch_target
    @target = Current.account.crm_sales_targets.find(params[:id])
  end

  def check_authorization
    authorize(Crm::SalesTarget)
  end

  # 我的目标 / 按月份。
  def filtered_targets
    scope = Current.account.crm_sales_targets
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.for_month(Date.parse(params[:month])) if params[:month].present?
    scope
  end

  def target_params
    params.require(:target).permit(:name, :target_month, :target_amount_micros, :target_order_count, :owner_id)
  end
end
