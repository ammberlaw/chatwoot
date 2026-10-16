# 生产订单的物料反馈面板：采购更新供应商那边的情况，业务只读。
class Api::V1::Accounts::Mes::OrderFeedbacksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_order
  before_action :fetch_feedback, only: [:destroy]

  def index
    @feedbacks = @order.order_feedbacks.includes(:user).recent_first
  end

  def create
    @feedback = @order.order_feedbacks.create!(
      account: Current.account, user: current_user, **feedback_params.to_h.symbolize_keys
    )
    render 'api/v1/accounts/mes/order_feedbacks/show'
  end

  # 发错了自己撤掉；别人写的不给删（管理员除外）。
  def destroy
    return render json: { error: '只能删自己发的反馈' }, status: :forbidden unless removable?(@feedback)

    @feedback.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(Mes::OrderFeedback)
  end

  def fetch_order
    @order = Current.account.mes_production_orders.find(params[:production_order_id])
  end

  def fetch_feedback
    @feedback = @order.order_feedbacks.find(params[:id])
  end

  def removable?(feedback)
    Current.account_user.administrator? || feedback.user_id == current_user.id
  end

  def feedback_params
    params.require(:order_feedback).permit(:kind, :body, :material_name, :promised_date)
  end
end
