# 物料反馈：MES 里的人都看得到（业务要照着它跟客户解释），只有采购能写。
class Mes::OrderFeedbackPolicy < ApplicationPolicy
  def index? = @account_user.mes_staff? || @account_user.crm_finance? || @account_user.administrator?
  def create? = @account_user.mes_can?(:purchase)
  def destroy? = @account_user.mes_can?(:purchase) || @account_user.administrator?
end

Mes::OrderFeedbackPolicy.prepend_mod_with('Mes::OrderFeedbackPolicy')
