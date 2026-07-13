class Api::V1::Accounts::Oa::ApprovalTemplatesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:update, :destroy]

  def index
    scope = Current.account.oa_approval_templates.ordered
    scope = scope.active if params[:active] == 'true'
    @templates = scope
  end

  def create
    @template = Current.account.oa_approval_templates.create!(template_params)
  end

  def update
    @template.update!(template_params)
  end

  def destroy
    @template.destroy!
    head :ok
  end

  private

  def fetch_template
    @template = Current.account.oa_approval_templates.find(params[:id])
  end

  def check_authorization
    authorize(Oa::ApprovalTemplate)
  end

  def template_params
    params.require(:template).permit(
      :name, :description, :icon, :active, :position,
      form_fields: [:key, :label, :type, :required, { options: [] }],
      flow: [:type, :user_id]
    )
  end
end
