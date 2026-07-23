class Api::V1::Accounts::Mes::StockEntriesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_stock_entry, only: [:show, :update, :destroy, :post]

  COLUMN_FILTERS = {
    purpose: :purpose, status: :status,
    production_order_id: :production_order_id, purchase_order_id: :purchase_order_id
  }.freeze

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_stock_entries))
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    @stock_entries_count = scope.count
    @stock_entries = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @stock_entry = Current.account.mes_stock_entries.new(
      stock_entry_params.merge(owner_id: stock_entry_params[:owner_id] || current_user.id)
    )
    @stock_entry.fallback_product_line = current_product_line
    @stock_entry.save!
    render 'api/v1/accounts/mes/stock_entries/show'
  end

  def update
    @stock_entry.update!(stock_entry_params)
    render 'api/v1/accounts/mes/stock_entries/show'
  end

  def destroy
    @stock_entry.destroy!
    head :ok
  end

  # 过账：刷结存 + 记流水 + 阶段推进。
  def post
    @stock_entry.post!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_stock_entry
    @stock_entry = Current.account.mes_stock_entries.find(params[:id])
  end

  def check_authorization
    authorize(Mes::StockEntry)
  end

  def stock_entry_params
    params.require(:stock_entry).permit(
      :purpose, :production_order_id, :purchase_order_id, :from_warehouse_id, :to_warehouse_id,
      :is_checked, :checked_by_id, :received_by_id, :owner_id, :remark,
      stock_entry_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :qty, :received_qty, :unit, :warehouse_id, :remark, :_destroy
      ]
    )
  end
end
