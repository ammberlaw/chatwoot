# 获客任务：CRM 成员都能建自己的；可见范围在控制器按负责人收口。
#
# ⚠️ 控制器每加一个 action，这里就要补一个同名方法，否则**直接 500**
# （NoMethodError: undefined method 'xxx?'）。2026-11-06 这一天栽了四次：
# preview_meta? / sales_snapshot? / sample 那次 / 这次的 leads?。
# 加 action 时顺手回来看一眼这个文件。
class Crm::LeadCampaignPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  # 业务员也能建自己的任务（用户 2026-11-08 定）。
  # 线索不归任务所有——谁领谁得，见 Crm::Lead 的 owner_id/claimed_at。
  def create? = true
  def update? = true
  def destroy? = true
  def build_profile? = true
  def search? = true
  def leads? = true
  def outcomes? = true
  # 管理端概览。能不能看在控制器里按角色判（policy 只管放行这个 action）。
  def team_stats? = true
  def keyword_library? = true
  def pool? = true
end

Crm::LeadCampaignPolicy.prepend_mod_with('Crm::LeadCampaignPolicy')
