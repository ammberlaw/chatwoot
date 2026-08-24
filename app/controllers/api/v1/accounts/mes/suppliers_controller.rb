class Api::V1::Accounts::Mes::SuppliersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_supplier, only: [:show, :update, :destroy]

  def index
    scope = filtered_scope
    @suppliers_count = scope.count
    @suppliers = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
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

  def filtered_scope
    scope = Current.account.mes_suppliers.includes(:supplier_items)
    scope = scope.where('name ILIKE :t OR supplier_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    scope = scope.where(is_active: true) if params[:active] == 'true'
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
      :product_line, :department, :category, :tax_rate, :invoice_title, :tax_no, :bank_name, :bank_account, :bank_address,
      supplier_items_attributes: [:id, :material_code, :category, :name, :color, :specification, :unit, :unit_price, :_destroy]
    )
  end
end
