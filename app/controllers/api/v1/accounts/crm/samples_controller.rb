# 寄样记录。客户详情页右列那块用它。
#
# 可见范围跟着客户走：看得到这个客户就看得到他的寄样（口径同客户详情页其余板块）。
class Api::V1::Accounts::Crm::SamplesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_sample, only: [:update, :destroy]

  def index
    # 可见范围跟着客户走：客户看得到，他的寄样就看得到（visible_customers 已含
    # 团队口径归属 + 被共享 + 公海，防越权读他人私海客户的单据）。
    scope = Current.account.crm_samples.includes(:owner, :crm_customer)
                   .where(crm_customer_id: visible_customers.select(:id))
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = scope.open_ones if params[:filter] == 'open'
    @samples = scope.recent_first.limit(params[:limit].presence&.to_i || 50)
  end

  def create
    @sample = Current.account.crm_samples.new(sample_params)
    @sample.owner_id ||= current_user.id
    # 建的时候就填了快递单号＝东西已经寄出去了，状态直接落「已寄出」，
    # 不逼人先存一版待寄出再改一次。
    @sample.status = 'SENT' if @sample.status == 'PENDING' && @sample.tracking_no.present?
    @sample.save!
    render :show
  end

  def update
    @sample.update!(sample_params)
    render :show
  end

  def destroy
    @sample.destroy!
    head :ok
  end

  private

  def fetch_sample
    @sample = Current.account.crm_samples
                     .where(crm_customer_id: visible_customers.select(:id)).find(params[:id])
  end

  def check_authorization
    authorize(Crm::Sample)
  end

  def sample_params
    params.require(:sample).permit(
      :crm_customer_id, :crm_opportunity_id, :owner_id, :status, :carrier, :tracking_no,
      :recipient, :sent_at, :delivered_at, :feedback_result, :feedback, :feedback_at, :remark,
      items: [:name, :model, :quantity]
    )
  end
end
