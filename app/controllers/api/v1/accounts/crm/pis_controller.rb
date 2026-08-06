class Api::V1::Accounts::Crm::PisController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_pi, only: [:show, :update, :destroy, :xlsx]

  RESULTS_PER_PAGE = 15

  def index
    scope = filtered_pis
    @pis_count = scope.count
    @pis = scope.includes(:crm_customer, :owner, pi_items: { picture_attachment: :blob })
                .order(pi_date: :desc, id: :desc)
                .page(permitted_params[:page] || 1)
                .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @pi = Current.account.crm_pis.new(pi_params)
    @pi.owner_id ||= current_user.id
    @pi.save!
    render :show
  end

  def update
    @pi.update!(pi_params)
    render :show
  end

  def destroy
    @pi.destroy!
    head :ok
  end

  # 导出 xlsx：把数据填进原始模板（真·1:1），流式下载。
  def xlsx
    stream = Crm::PiTemplateFiller.new(@pi).to_stream
    send_data stream.read,
              filename: "PI-#{@pi.pi_no}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 选客户后预填买方快照（业务仍可改）。EORI 客户档案没有，留空。
  def prefill
    customer = Current.account.crm_customers.find(params[:customer_id])
    render json: {
      attention: customer.primary_contact_name,
      buyer_company: customer.name,
      buyer_address: customer.address,
      buyer_email: customer.contact_email,
      buyer_tel: customer.contact_phone,
      port_of_destination: customer.trade_country
    }
  end

  private

  def fetch_pi
    @pi = Current.account.crm_pis.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Pi)
  end

  def filtered_pis
    scope = scope_by_owner(Current.account.crm_pis)
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = search(scope, params[:q]) if params[:q].present?
    scope
  end

  # 搜索：PI号 / 买方公司 / 关联客户名。
  def search(scope, query)
    term = "%#{query.strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_pis.pi_no ILIKE :t OR crm_pis.buyer_company ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  def pi_params
    params.require(:pi).permit(
      :pi_no, :pi_date, :status, :currency, :crm_customer_id, :contact_id, :owner_id,
      :attention, :buyer_company, :buyer_address, :buyer_email, :buyer_tel, :buyer_eori,
      :port_of_shipment, :port_of_destination, :country_of_origin, :shipping_method,
      :shipping_cost_label, :shipping_cost_micros, :terms, :issued_by, :remark,
      pi_items_attributes: [
        :id, :position, :model, :description, :quantity, :unit_price_micros, :picture, :_destroy
      ]
    )
  end

  def permitted_params
    params.permit(:page, :filter, :status, :q)
  end
end
