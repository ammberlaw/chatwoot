# ERP（财务管理）所有控制器的基类：统一「能否进入 ERP」门禁。
# 门禁：管理员/副管理员，或被赋予 erp_role 且 ERP 模块开关打开者可入；其他（含纯销售角色）一律 403。
# 生态硬约束：ERP 承载成本/供应商/毛利，销售端绝不可入。
# 后续切片的能力细分（应收/应付/出纳/凭证…）在各控制器内按 erp_can? 自行细校验，基类只管门禁。
class Api::V1::Accounts::Erp::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  before_action :ensure_erp_access

  private

  def ensure_erp_access
    return if Current.account_user&.can_access_erp?

    render json: { error: I18n.t('errors.erp.no_access', default: '无权访问财务 ERP') }, status: :forbidden
  end

  def page_param
    params[:page] || 1
  end
end
