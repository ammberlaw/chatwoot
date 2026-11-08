# 线索：可见范围在控制器按任务负责人收口，这里只放行动作。
class Crm::LeadPolicy < ApplicationPolicy
  def show? = true
  def unlock? = true
  def take? = true
  def release? = true
  def claim? = true
  def discard? = true
  def ai_bg_check? = true
end

Crm::LeadPolicy.prepend_mod_with('Crm::LeadPolicy')
