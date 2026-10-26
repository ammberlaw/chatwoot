# 收信黑名单：规则是全公司生效的（一条规则挡所有人的信），所以只给管理员维护。
# 不能让单个业务员拉黑一个域名就把别人的客户来信也掐掉。
class Crm::MailBlocklistPolicy < ApplicationPolicy
  def index? = manage?
  def create? = manage?
  def destroy? = manage?

  private

  def manage?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end
