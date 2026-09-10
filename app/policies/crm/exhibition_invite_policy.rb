class Crm::ExhibitionInvitePolicy < ApplicationPolicy
  # 具体数据范围由控制器 fetch_invite 的 scope_by_team_owner 强制，越权自然 404。
  def destroy?
    true
  end

  def compose?
    true
  end

  def advance?
    true
  end
end

Crm::ExhibitionInvitePolicy.prepend_mod_with('Crm::ExhibitionInvitePolicy')
