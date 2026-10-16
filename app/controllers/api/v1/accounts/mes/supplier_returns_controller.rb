# 退料返修单：退给供应商修，修好登记回来。只记台账，不动库存（见 Mes::SupplierReturn）。
class Api::V1::Accounts::Mes::SupplierReturnsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_return, only: [:show, :update, :destroy, :send_out, :receive_back]

  RESULTS_PER_PAGE = 20

  def index
    scope = scoped_by_product_line(Current.account.mes_supplier_returns)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    scope = apply_search(scope, params[:q])
    @returns_count = scope.count
    @returns = scope.includes(:mes_supplier, :production_order, :owner, items: :crm_product)
                    .order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @supplier_return = Current.account.mes_supplier_returns.new(
      supplier_return_params.merge(owner_id: current_user.id)
    )
    @supplier_return.fallback_product_line = current_product_line
    @supplier_return.save!
    render 'api/v1/accounts/mes/supplier_returns/show'
  end

  def update
    @supplier_return.update!(supplier_return_params)
    render 'api/v1/accounts/mes/supplier_returns/show'
  end

  def destroy
    return render json: { error: '已经退出去的单不能删，请走关闭' }, status: :unprocessable_entity if @supplier_return.sent_on

    @supplier_return.destroy!
    head :ok
  end

  # 退出去：记日期，进「已退出」。
  def send_out = render_after { @supplier_return.send_out!(on: params[:sent_on]) }

  # 登记返回：rows = [{ id:, returned_qty: }]，累加到各行的已返回数。
  def receive_back
    render_after { @supplier_return.receive_back!(params[:rows], on: params[:returned_on]) }
  end

  private

  def render_after
    yield
    render 'api/v1/accounts/mes/supplier_returns/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def apply_search(scope, raw)
    q = raw.to_s.strip
    return scope if q.blank?

    like = "%#{q}%"
    scope.where('mes_supplier_returns.return_no ILIKE :q OR mes_supplier_returns.reason ILIKE :q', q: like)
  end

  def fetch_return
    @supplier_return = Current.account.mes_supplier_returns.find(params[:id])
  end

  def check_authorization
    authorize(Mes::SupplierReturn)
  end

  def supplier_return_params
    params.require(:supplier_return).permit(
      :return_no, :mes_supplier_id, :production_order_id, :product_line, :reason, :remark, :sent_on,
      items_attributes: [:id, :crm_product_id, :qty, :unit, :remark, :_destroy]
    )
  end
end
