# 收信黑名单：全员可用，但**范围**分两级——
# 业务员建的规则只拦自己名下的信；全公司规则只有管理员/副管能建能删。
# 这里只放行到「能不能访问这个接口」，范围收口在控制器 can_manage_global?：
# policy 看不见规则本身，判不了这条是谁的。
class Crm::MailBlocklistPolicy < ApplicationPolicy
  def index? = true
  def create? = true
  def destroy? = true
end
