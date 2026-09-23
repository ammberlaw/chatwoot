# 账号密码：能否进入由控制器按分组名单判定（管理员/副管直通），故策略层只做「已登录成员」放行。
class Crm::CredentialPolicy < ApplicationPolicy
  def index? = true
  def views? = true
  def reveal? = true
  def create? = true
  def update? = true
  def destroy? = true
end

Crm::CredentialPolicy.prepend_mod_with('Crm::CredentialPolicy')
