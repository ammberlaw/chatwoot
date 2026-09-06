# 自动凭证规则：预置三条（收款/付款/划转），可停用、可改科目映射。
class Api::V1::Accounts::Erp::AutoVoucherRulesController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  def index
    @rules = Erp::AutoVoucherRule.ensure_defaults!(Current.account)
  end

  def update
    @rule = Current.account.erp_auto_voucher_rules.find(params[:id])
    @rule.update!(rule_params)
    render 'api/v1/accounts/erp/auto_voucher_rules/show'
  end

  private

  def check_authorization
    authorize(Erp::AutoVoucherRule)
  end

  def rule_params
    params.require(:rule).permit(:is_active, :remark, config: {})
  end
end
