class Erp::FixedAssetPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:asset)
  def update? = @account_user.erp_can?(:asset)
  def destroy? = @account_user.erp_can?(:asset)
  def depreciate? = @account_user.erp_can?(:asset)
  def dispose? = @account_user.erp_can?(:asset)
end

Erp::FixedAssetPolicy.prepend_mod_with('Erp::FixedAssetPolicy')
