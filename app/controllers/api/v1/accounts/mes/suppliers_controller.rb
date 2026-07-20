class Api::V1::Accounts::Mes::SuppliersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_supplier, only: [:show, :update, :destroy]

  def index
    scope = Current.account.mes_suppliers
    scope = scope.where('name ILIKE :t OR supplier_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    scope = scope.where(is_active: true) if params[:active] == 'true'
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

  def fetch_supplier
    @supplier = Current.account.mes_suppliers.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Supplier)
  end

  def supplier_params
    params.require(:supplier).permit(
      :supplier_no, :name, :contact_name, :phone, :email, :address, :owner_id, :is_active, :remark
    )
  end
end
