# 凭证模板：每月重复的分录存一份，新建凭证时一键带出。模板不参与记账。
class Api::V1::Accounts::Erp::VoucherTemplatesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  def index
    @templates = Current.account.erp_voucher_templates.order(:name)
  end

  def create
    @template = Current.account.erp_voucher_templates.create!(template_params.merge(created_by_id: current_user.id))
    render 'api/v1/accounts/erp/voucher_templates/show'
  end

  def destroy
    Current.account.erp_voucher_templates.find(params[:id]).destroy!
    head :ok
  end

  private

  def template_params
    params.require(:template).permit(:name, :summary, lines: Erp::VoucherTemplate::LINE_KEYS.map(&:to_sym))
  end

  def check_authorization
    authorize(Erp::VoucherTemplate)
  end
end
