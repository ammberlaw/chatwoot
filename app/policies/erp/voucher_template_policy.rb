class Erp::VoucherTemplatePolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?

  # 模板是录入工具，跟凭证同一个能力域。
  def create? = @account_user.erp_can?(:voucher)
  def destroy? = @account_user.erp_can?(:voucher)
end

Erp::VoucherTemplatePolicy.prepend_mod_with('Erp::VoucherTemplatePolicy')
