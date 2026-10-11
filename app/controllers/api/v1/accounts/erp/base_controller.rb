# ERP（财务管理）所有控制器的基类：统一「能否进入 ERP」门禁。
# 门禁：管理员/副管理员，或被赋予 erp_role 且 ERP 模块开关打开者可入；其他（含纯销售角色）一律 403。
# 生态硬约束：ERP 承载成本/供应商/毛利，销售端绝不可入。
# 后续切片的能力细分（应收/应付/出纳/凭证…）在各控制器内按 erp_can? 自行细校验，基类只管门禁。
class Api::V1::Accounts::Erp::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  include PaginationParamNormalizer

  before_action :ensure_erp_access

  private

  def ensure_erp_access
    return if Current.account_user&.can_access_erp?

    render json: { error: I18n.t('errors.erp.no_access', default: '无权访问财务 ERP') }, status: :forbidden
  end

  def page_param
    params[:page] || 1
  end

  # 前端可传 per_page（snake_case）加大每页条数；不传按默认 15。上限 100 防一把拉全表。
  def per_page_param
    params[:per_page].present? ? params[:per_page].to_i.clamp(1, 100) : RESULTS_PER_PAGE
  end

  # 冻结期闸（收付款单 update/void 共用）：给定日期里任何一个落在已结账期间就返回该期间号。
  def closed_period_for(*dates)
    dates.compact.map { |d| d.to_date.strftime('%Y-%m') }.uniq
         .find { |period| Erp::FiscalPeriod.closed?(Current.account, period) }
  end

  # 账龄分析的两个入参（应收/应付两个控制器共用）。
  def aging_as_of
    params[:as_of].presence&.to_date || Time.zone.today
  end

  def aging_basis
    params[:basis] == Erp::AgingService::INVOICE ? Erp::AgingService::INVOICE : Erp::AgingService::DUE
  end
end
