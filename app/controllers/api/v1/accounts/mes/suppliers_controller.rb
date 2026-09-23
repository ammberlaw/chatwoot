class Api::V1::Accounts::Mes::SuppliersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_supplier, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @suppliers_count = scope.count
    @suppliers = scope.order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @supplier = Current.account.mes_suppliers.create!(supplier_params)
    render 'api/v1/accounts/mes/suppliers/show'
  end

  def update
    @supplier.update!(supplier_params)
    render 'api/v1/accounts/mes/suppliers/show'
  end

  def destroy
    @supplier.destroy!
    head :ok
  end

  private

  # 默认 15/页；采购单/物料表单的供应商下拉需要全量，可传 per_page，封顶 500。
  def per_page_param
    n = params[:per_page].to_i
    return RESULTS_PER_PAGE if n <= 0

    [n, 500].min
  end

  def filtered_scope
    scope = Current.account.mes_suppliers.includes(:supplier_items)
    scope = scope.where('name ILIKE :t OR supplier_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    scope = scope.where(is_active: true) if params[:active] == 'true'
    # 按事业部（产品线）筛供应商
    scope = scope.where(product_line: params[:product_line]) if params[:product_line].present?
    # 按供应物料的 SKU 分类筛供应商（如找「供辅料的供应商」）
    scope = scope.joins(:supplier_items).where(mes_supplier_items: { category: params[:item_category] }).distinct if params[:item_category].present?
    scope
  end

  def fetch_supplier
    @supplier = Current.account.mes_suppliers.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Supplier)
  end

  def supplier_params
    params.require(:supplier).permit(
      :supplier_no, :name, :contact_name, :phone, :email, :address, :owner_id, :is_active, :remark,
      :product_line, :department, :category, :tax_rate, :invoice_title, :tax_no, :bill_entity, :bank_name, :bank_account, :bank_address,
      supplier_items_attributes: [:id, :material_code, :category, :name, :color, :specification, :unit, :unit_price, :_destroy]
    )
  end
end
