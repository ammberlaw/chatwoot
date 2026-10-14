class Erp::PayablePolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?
  def open_list? = @account_user.can_access_erp?
  def supplier_statement? = @account_user.can_access_erp?
  def aging? = @account_user.can_access_erp?
  def monthly? = @account_user.can_access_erp?
  def detail? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:payable)
  def update? = @account_user.erp_can?(:payable)
  def destroy? = @account_user.erp_can?(:payable)
end

Erp::PayablePolicy.prepend_mod_with('Erp::PayablePolicy')
