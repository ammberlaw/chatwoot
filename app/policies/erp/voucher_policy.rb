class Erp::VoucherPolicy < ApplicationPolicy
  # 读：能进 ERP 的成员即可（基类已挡销售端）。
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?

  # 写与状态流转：限 voucher 能力域（财务/管理员/副管理员）。出纳只录收付款，不碰凭证。
  def create? = @account_user.erp_can?(:voucher)
  def update? = @account_user.erp_can?(:voucher)
  def destroy? = @account_user.erp_can?(:voucher)
  def post_voucher? = @account_user.erp_can?(:voucher)
  def reverse? = @account_user.erp_can?(:voucher)
  def void? = @account_user.erp_can?(:voucher)
end

Erp::VoucherPolicy.prepend_mod_with('Erp::VoucherPolicy')
