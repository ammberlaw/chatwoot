class Erp::PayablePolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?
  def open_list? = @account_user.can_access_erp?
  def supplier_statement? = @account_user.can_access_erp?
  def monthly_statement? = @account_user.can_access_erp?
  def monthly_statement_detail? = @account_user.can_access_erp?
  def aging? = @account_user.can_access_erp?
  def monthly? = @account_user.can_access_erp?
  def detail? = @account_user.can_access_erp?
  # 名单谁都能看（财务要知道哪些单没入账）；真去补凭证要记账权限。
  def pending_vouchers? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:payable)
  def update? = @account_user.erp_can?(:payable)
  def destroy? = @account_user.erp_can?(:payable)
  def build_receipt_voucher? = @account_user.erp_can?(:voucher)
  # 待对账清单（Erp::PayableReconciliationsController）：看清单同 index?，确认建账要建账权限。
  def confirm? = @account_user.erp_can?(:payable)
end

Erp::PayablePolicy.prepend_mod_with('Erp::PayablePolicy')
