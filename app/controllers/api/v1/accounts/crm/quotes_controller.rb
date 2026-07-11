class Api::V1::Accounts::Crm::QuotesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_quote, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @quotes_scope = filtered_quotes
    @quotes_count = @quotes_scope.count
    @quotes = @quotes_scope
              .order(updated_at: :desc)
              .page(permitted_params[:page] || 1)
              .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @quote = Current.account.crm_quotes.create!(quote_params)
  end

  def update
    @quote.update!(quote_params)
  end

  def destroy
    @quote.destroy!
    head :ok
  end

  private

  def fetch_quote
    @quote = Current.account.crm_quotes.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Quote)
  end

  # 视图筛选：待处理报价(DRAFT/SENT)、我的、按状态、按客户。
  def filtered_quotes
    scope = Current.account.crm_quotes
    scope = scope.pending if params[:filter] == 'pending'
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  def quote_params
    params.require(:quote).permit(
      :name, :quote_no, :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :quote_date, :valid_until, :status, :quote_currency, :exchange_rate,
      :subtotal_micros, :discount_amount_micros, :shipping_fee_micros,
      :tax_amount_micros, :total_amount_micros, :remark
    )
  end

  def permitted_params
    params.permit(:page, :filter, :status, :customer_id)
  end
end
