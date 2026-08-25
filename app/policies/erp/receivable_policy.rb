class Erp::ReceivablePolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?
  def open_list? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:receivable)
  def update? = @account_user.erp_can?(:receivable)
  def destroy? = @account_user.erp_can?(:receivable)
end

Erp::ReceivablePolicy.prepend_mod_with('Erp::ReceivablePolicy')
