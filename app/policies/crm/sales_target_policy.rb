class Crm::SalesTargetPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  # 目标体检 / 一键按底线补：页面会摆出每个人的保本线，而保本线＝月薪 ÷ 有效提成率，
  # 知道点位就能反推月薪。所以按**薪资数据同一口径**收口，和薪资表是同一批人。
  # 主管不给——他要看下属目标，去团队看板。
  def audit?
    salary_like?
  end

  def seed?
    salary_like?
  end

  private

  def salary_like?
    @account_user.administrator? || @account_user.crm_deputy_admin? || @account_user.crm_hr?
  end
end

Crm::SalesTargetPolicy.prepend_mod_with('Crm::SalesTargetPolicy')
