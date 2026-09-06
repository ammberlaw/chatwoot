# 收付款是出纳的活：payment 能力域（财务与出纳都有）。
class Erp::PaymentRecordPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:payment)
  def update? = @account_user.erp_can?(:payment)
  def destroy? = @account_user.erp_can?(:payment)
  def void? = @account_user.erp_can?(:payment)
end

Erp::PaymentRecordPolicy.prepend_mod_with('Erp::PaymentRecordPolicy')
