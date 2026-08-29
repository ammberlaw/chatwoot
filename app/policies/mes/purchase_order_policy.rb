class Mes::PurchaseOrderPolicy < ApplicationPolicy
  # 明细挂供应商、单头有采购金额，销售端不可见（生态硬约束）；
  # 业务员看生产进度走生产订单阶段名，不需要读采购单。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?
  def requirement? = @account_user.mes_staff?
  # 按供应商拆单导出（发供应商用），与查看同权。
  def export? = @account_user.mes_staff?
  def export_data? = @account_user.mes_staff?

  def create? = @account_user.mes_can?(:purchase)
  def update? = @account_user.mes_can?(:purchase)

  # 提交审批：采购员本人。审批/驳回：总经理或管理员（代批）。
  def submit? = @account_user.mes_can?(:purchase)
  def approval_inbox? = @account_user.mes_staff?
  def approve? = gm_or_admin?
  def reject? = gm_or_admin?

  def return_document? = @account_user.mes_can?(:purchase)
  def reactivate? = @account_user.mes_can?(:purchase)

  def destroy? = @account_user.administrator?

  private

  # 总经理 = 绩效设置里的 gm_owner_id；管理员可代批。
  def gm_or_admin?
    return true if @account_user.administrator?

    Crm::PerformanceSetting.for_account(@account)&.gm_owner_id == @user.id
  end
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
