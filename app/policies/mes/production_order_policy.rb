class Mes::ProductionOrderPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def requirement? = true
  def issue_plan? = true
  def inbox? = true
  def audits? = true
  # 业务知会/转发给阶段负责人：任何可见订单的人都能发（只是内部知会，不改订单状态）。
  def forward? = true
  # 接单/拒收的细粒度权限（本阶段负责人 or 管理员）在控制器 can_handle_stage? 内校验。
  def acknowledge? = true
  # 转交给同阶段另一位负责人：与接单同权（控制器再校验「必须是本阶段负责人」）。
  def handoff? = true
  def reject? = true
  # 业务二次确认 BOM（控制器校验创建人/管理员）。
  # 审批链：提交（控制器校验创建人）、通过/驳回（控制器 can_approve? 校验当前环节人/管理员）、待我审批收件箱。
  def submit_approval? = true
  def approve? = true
  def deny? = true
  def approval_inbox? = true

  # 建单/编辑放开给 CRM 业务角色——业务员建定制单走「草稿→三级审批」流转；
  # 无 :order 能力者仅限本人草稿+按单生产（控制器 ensure_own_draft! 收紧）。
  def create? = @account_user.mes_can?(:order) || @account_user.can_access_crm?
  # 「从销售订单转入」与建单同权。绕不绕审批链由控制器按能力分：
  # :order 能力者转入直接 APPROVED（原样）；业务员转入＝提交审批，审批链一步不少。
  def convert? = create?
  # 暂存 blob（建单前上传）：与建单同权限。
  def stage_blob? = create?
  # 挂 BOM / 下发采购：工程 + PMC（order 或 bom 能力）。
  def attach_bom? = @account_user.mes_can?(:order) || @account_user.mes_can?(:bom)
  def release_purchasing? = attach_bom?
  # 解绑 BOM / 采购退回 BOM 阶段：都是挂错了的纠错动作，与挂 BOM 同权（工程/PMC）。
  def detach_bom? = attach_bom?
  def revert_to_bom_ready? = attach_bom?
  # 标记外购：与挂 BOM 同权（工程/PMC）——它是挂 BOM 的外购分支替代。
  def mark_outsourced? = attach_bom?
  def update? = @account_user.mes_can?(:order) || @account_user.can_access_crm?
  # 产品图片/附件：与编辑同权限。
  def attach? = update?
  def detach? = update?
  # 产品编码：由工程/PMC 编写（bom 能力）。
  def set_product_code? = @account_user.mes_can?(:bom)

  # 归属业务可删本人草稿（控制器 ensure_deletable! 收紧到「本人 + 草稿」）；管理员删任意。
  def destroy? = @account_user.administrator? || @account_user.mes_can?(:order) || @account_user.can_access_crm?
end

Mes::ProductionOrderPolicy.prepend_mod_with('Mes::ProductionOrderPolicy')
