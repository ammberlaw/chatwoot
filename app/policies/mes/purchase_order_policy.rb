class Mes::PurchaseOrderPolicy < ApplicationPolicy
  # 明细挂供应商、单头有采购金额，销售端不可见（生态硬约束）；
  # 业务员看生产进度走生产订单阶段名，不需要读采购单。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?
  def requirement? = @account_user.mes_staff?
  # 按供应商拆单导出（发供应商用，含采购价）：金额敏感，仅采购岗/财务/管理员可导。
  def export? = can_view_amount?
  def export_data? = can_view_amount?

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

  # 采购金额（含税单价/总额/导出）可见：采购岗 / 财务 / 管理员。仓管等其它岗位不可见。
  def can_view_amount?
    @account_user.mes_can?(:purchase) || @account_user.crm_finance?
  end

  private

  # 总经理 = 绩效设置里的 gm_owner_id；管理员可代批。
  def gm_or_admin?
    return true if @account_user.administrator?

    Crm::PerformanceSetting.for_account(@account)&.gm_owner_id == @user.id
  end
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
