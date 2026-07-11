class Api::V1::Accounts::Crm::CustomersController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_customer, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @customers_scope = filtered_customers
    @customers_count = @customers_scope.count
    @customers = @customers_scope
                 .order(updated_at: :desc)
                 .page(permitted_params[:page] || 1)
                 .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @customer = Current.account.crm_customers.create!(customer_params)
  end

  # 客户建档实时查重：邮箱精确命中(阻止) + 公司名相似(提醒)。
  def check_duplicate
    email = params[:email].to_s.strip
    name = params[:name].to_s.strip
    render json: {
      email_hit: email.present? ? dedupe_row(Current.account.crm_customers.where('LOWER(contact_email) = ?', email.downcase).first) : nil,
      name_hits: name.length >= 2 ? name_matches(name) : []
    }
  end

  def update
    @customer.update!(customer_params)
  end

  def destroy
    @customer.destroy!
    head :ok
  end

  private

  def fetch_customer
    @customer = Current.account.crm_customers.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  # 支持常用视图筛选：公海池、我的客户、未分配、按状态。
  def filtered_customers
    scope = Current.account.crm_customers
    case params[:filter]
    when 'public_pool'
      scope = scope.in_public_pool
    when 'private'
      scope = scope.where(is_in_public_pool: false)
    when 'mine'
      scope = scope.owned_by(current_user.id)
    when 'unassigned'
      scope = scope.where(account_owner_id: nil, is_in_public_pool: false)
    end
    scope = scope.where(customer_status: params[:status]) if params[:status].present?
    scope = scope.owned_by(params[:account_owner_id]) if params[:account_owner_id].present?
    scope
  end

  def customer_params
    params.require(:customer).permit(
      :name, :customer_code, :account_owner_id, :website,
      :trade_country, :trade_region, :trade_city,
      :industry, :customer_level, :source_channel, :currency_preference,
      :customer_status, :customer_group, :product_group, :risk_level,
      :last_follow_up_at, :next_follow_up_at, :is_in_public_pool, :public_pool_at,
      :primary_contact_name, :contact_job_title, :contact_email, :contact_phone,
      :whats_app, :wechat, :contact_preference, :customer_remark
    )
  end

  def name_matches(name)
    Current.account.crm_customers
           .where('name ILIKE ?', "%#{name}%")
           .order(updated_at: :desc).limit(5)
           .map { |c| dedupe_row(c) }
  end

  # 查重结果行：含负责人归属标签（公海/负责人/未分配）
  def dedupe_row(customer)
    return nil if customer.nil?

    { id: customer.id, name: customer.name, customer_code: customer.customer_code, owner: owner_label(customer) }
  end

  def owner_label(customer)
    return '🌊 公海' if customer.is_in_public_pool
    return "👤 #{customer.account_owner.name}" if customer.account_owner_id

    '未分配'
  end

  def permitted_params
    params.permit(:page, :filter, :status, :account_owner_id)
  end
end
