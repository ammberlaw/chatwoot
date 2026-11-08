# 寄样记录：CRM 成员都能记、能改自己客户的。
# 真正的收口在控制器（按 visible_customers 限定），这里只放行动作——
# 少写一个方法就是 500（今天已经栽过两次：preview_meta?、sales_snapshot?）。
class Crm::SamplePolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def create? = true
  def update? = true
  def destroy? = true
end

Crm::SamplePolicy.prepend_mod_with('Crm::SamplePolicy')
