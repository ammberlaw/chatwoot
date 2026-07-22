class Api::V1::Accounts::Mes::BomTemplatesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:show, :update, :destroy]

  def index
    scope = scoped_by_product_line(Current.account.mes_bom_templates)
    scope = scope.where('name ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @templates = scope.order(updated_at: :desc)
  end

  def show; end

  def create
    @template = Current.account.mes_bom_templates.new(template_params)
    @template.fallback_product_line = current_product_line
    @template.owner_id ||= Current.user&.id
    @template.save!
    render 'api/v1/accounts/mes/bom_templates/show'
  end

  def update
    @template.update!(template_params)
    render 'api/v1/accounts/mes/bom_templates/show'
  end

  def destroy
    @template.destroy!
    head :ok
  end

  private

  def fetch_template
    @template = Current.account.mes_bom_templates.find(params[:id])
  end

  def check_authorization
    authorize(Mes::BomTemplate)
  end

  def template_params
    params.require(:bom_template).permit(
      :name, :base_qty, :unit, :owner_id, :remark, :product_line,
      :purchasing_days, :material_inbound_days, :picking_days, :production_days, :fg_inbound_days,
      bom_template_items_attributes: [:id, :material_no, :material_name, :specification, :qty, :unit, :remark, :_destroy]
    )
  end
end
