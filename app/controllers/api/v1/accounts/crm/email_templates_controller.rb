class Api::V1::Accounts::Crm::EmailTemplatesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:show, :update, :destroy]

  def index
    scope = Current.account.crm_email_templates
    scope = scope.where(category: params[:category]) if params[:category].present?
    @templates = scope.order(:category, :name)
  end

  def show; end

  def create
    @template = Current.account.crm_email_templates.create!(template_params)
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
    @template = Current.account.crm_email_templates.find(params[:id])
  end

  def check_authorization
    authorize(Crm::EmailTemplate)
  end

  def template_params
    params.require(:template).permit(:name, :category, :subject_template, :body, :description)
  end
end
