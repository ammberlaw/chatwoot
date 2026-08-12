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
    apply_seller_profile_defaults
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
  # 卖方落款（联系人/手机/邮箱）缺失则拦住——提示业务员先填「我的卖方信息」预录。
  def xlsx
    if [@pi.issued_by, @pi.seller_mobile, @pi.seller_email].any?(&:blank?)
      return render json: { error: '请先填写「我的卖方信息」（PI 落款：联系人 / 手机 / 邮箱）' }, status: :unprocessable_entity
    end

    stream = Crm::PiTemplateFiller.new(@pi).to_stream
    send_data stream.read,
              filename: "PI-#{@pi.pi_no}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 公司抬头下拉选项（3 选 1 的主体列表，导出时公司名/地址/银行按此填）。
  def company_headers
    render json: Crm::PiTemplateFiller.header_options
  end

  # 读取 PI 自动识别：上传 PDF/Excel，返回字段化结果供前端校对（不落库）。与订单自动填单同引擎。
  def parse_pi
    return render json: { error: '请上传 PI 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Crm::PiParseService.new(account: Current.account, user: current_user, file: params[:file]).call
    render json: result
  rescue Crm::PiParseService::UnsupportedType, Crm::EmailAiService::NotConfigured => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PI parse] #{e.class}: #{e.message}")
    render json: { error: 'PI 识别失败，请检查文件或稍后重试' }, status: :unprocessable_entity
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

  # 建单时用业务员预录兜底卖方落款（前端一般已带入；此处兜住前端没传的情况）。
  # 联系人姓名复用 issued_by 列（Contact 行与 ISSUED BY 行同名）。
  def apply_seller_profile_defaults
    profile = Current.account.crm_pi_seller_profiles.owned_by(@pi.owner_id).first
    return unless profile

    @pi.issued_by = profile.contact_name if @pi.issued_by.blank?
    @pi.seller_mobile = profile.mobile if @pi.seller_mobile.blank?
    @pi.seller_email = profile.email if @pi.seller_email.blank?
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
      :pi_no, :pi_date, :status, :currency, :crm_customer_id, :contact_id, :owner_id, :company_header,
      :attention, :buyer_company, :buyer_address, :buyer_email, :buyer_tel, :buyer_eori,
      :port_of_shipment, :port_of_destination, :country_of_origin, :shipping_method,
      :shipping_cost_label, :shipping_cost_micros, :terms, :issued_by, :remark,
      :seller_mobile, :seller_email,
      pi_items_attributes: [
        :id, :position, :model, :description, :quantity, :unit_price_micros, :picture, :_destroy
      ]
    )
  end

  def permitted_params
    params.permit(:page, :filter, :status, :q)
  end
end
