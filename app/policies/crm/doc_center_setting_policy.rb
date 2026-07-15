# 文档中心负责人设置：全员可读（用于前端判断按钮可见性），仅管理员可改。
class Crm::DocCenterSettingPolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    @account_user.administrator?
  end
end

Crm::DocCenterSettingPolicy.prepend_mod_with('Crm::DocCenterSettingPolicy')
