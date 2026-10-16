class Mes::PurchaseOrderPolicy < ApplicationPolicy
  # 明细挂供应商、单头有采购金额，销售端不可见（生态硬约束）；
  # 业务员看生产进度走生产订单阶段名，不需要读采购单。
  # 采购审批人（按产线配置，可以是不兼 MES 岗的副总经理）能读——要批就得看得见单和金额。
  def index? = readable?
  def show? = readable?
  def requirement? = @account_user.mes_staff?

  # 上次采购价：只有看得见金额的岗位能问（同 export? 的成本口径）。
  def last_price? = @account_user.mes_can?(:purchase) || @account_user.crm_finance? || @account_user.administrator?
  # 按供应商拆单导出（发供应商用，含采购价）：这份文件要发出去，仍只给采购岗/财务/管理员，
  # 审批人不在内（他只需要在系统里看，不需要对外发单）。
  def export? = exportable?
  def export_data? = exportable?
  # 导出计次：能导出就能记次。
  def mark_exported? = exportable?

  def create? = @account_user.mes_can?(:purchase)
  def update? = @account_user.mes_can?(:purchase)
  # 明细行内部附图：能改单就能传图。
  def stage_blob? = @account_user.mes_can?(:purchase)

  # 提交审批：采购员本人。审批/驳回：本单审批人或管理员（代批）——本单是否归他批由控制器按
  # gm_id 逐单核对（authorize 这里拿不到记录，只能拦掉「完全没有审批身份的人」）。
  def submit? = @account_user.mes_can?(:purchase)
  def approval_inbox? = readable?
  def approve? = approver_or_admin?
  def reject? = approver_or_admin?

  def return_document? = @account_user.mes_can?(:purchase)
  def reactivate? = @account_user.mes_can?(:purchase)
  # 关闭 / 启用：能改单就能关、能再开（控制器另按建单人本人或管理员收口）。
  def close? = @account_user.mes_can?(:purchase)
  def reopen? = @account_user.mes_can?(:purchase)

  # 草稿删除：采购员自己建的废稿要能清掉（控制器 deletable? 限定只有未提审、未到货的草稿）。
  def destroy? = @account_user.administrator? || @account_user.mes_can?(:purchase)

  # 采购金额（含税单价/总额）可见：采购岗 / 财务 / 管理员 / 采购审批人。仓管等其它岗位不可见。
  def can_view_amount?
    @account_user.mes_can?(:purchase) || @account_user.crm_finance? || purchase_approver?
  end

  private

  # 财务（crm_finance）只读：对账要核「这批料花了多少、什么时候到的」，
  # 而导出早就放行给财务了（exportable? 含 crm_finance?）——只能导出却打不开列表，是口径不一致。
  # 只给读：建单/改单/审批仍要 purchase 能力或本单审批人。
  def readable? = @account_user.mes_staff? || purchase_approver? || @account_user.crm_finance?

  def exportable? = @account_user.mes_can?(:purchase) || @account_user.crm_finance?

  # 配置在任一产品线上的采购审批人（Mes::BoardOwner）。
  def purchase_approver? = Mes::PurchaseOrder.approver?(@account, @user.id)

  # 审批人本人或管理员（代批）。总经理照旧能批——他是「通用/商显」那条配置或回落里的人。
  def approver_or_admin?
    return true if @account_user.administrator?
    return true if purchase_approver?

    Crm::PerformanceSetting.for_account(@account)&.gm_owner_id == @user.id
  end
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
