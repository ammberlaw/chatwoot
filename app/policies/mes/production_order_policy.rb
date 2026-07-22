class Mes::ProductionOrderPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def requirement? = true
  def inbox? = true
  def audits? = true
  # 接单/拒收的细粒度权限（本阶段负责人 or 管理员）在控制器 can_handle_stage? 内校验。
  def acknowledge? = true
  def reject? = true
  # 业务二次确认 BOM（控制器校验创建人/管理员）。
  def confirm_bom? = true
  # 审批链：提交（控制器校验创建人）、通过/驳回（控制器 can_approve? 校验当前环节人/管理员）、待我审批收件箱。
  def submit_approval? = true
  def approve? = true
  def deny? = true
  def approval_inbox? = true

  def create? = @account_user.mes_can?(:order)
  def convert? = @account_user.mes_can?(:order)
  # 暂存 blob（建单前上传）：与建单同权限。
  def stage_blob? = create?
  # 挂 BOM / 下发采购：工程 + PMC（order 或 bom 能力）。
  def attach_bom? = @account_user.mes_can?(:order) || @account_user.mes_can?(:bom)
  def release_purchasing? = attach_bom?
  def update? = @account_user.mes_can?(:order)
  # 产品图片/附件：与编辑同权限。
  def attach? = update?
  def detach? = update?
  # 产品编码：由工程/PMC 编写（bom 能力）。
  def set_product_code? = @account_user.mes_can?(:bom)

  def destroy? = @account_user.administrator?
end

Mes::ProductionOrderPolicy.prepend_mod_with('Mes::ProductionOrderPolicy')
