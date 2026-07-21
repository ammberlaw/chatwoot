# MES 所有控制器的基类。S0：任何本账号成员均可访问（生产/仓管/采购未必有 crm_role）；
# 角色收敛留到 S8。数据均以 Current.account 多租户隔离。
class Api::V1::Accounts::Mes::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  private

  def page_param
    params[:page] || 1
  end

  # 当前切换的产品线（DISPLAY/TABLET），前端 axios 拦截自动注入；空=全部。
  def current_product_line
    params[:product_line].presence
  end

  # 按当前产品线收敛列表（供应商/仓库为共享物理资源，不参与分流，故不调用）。
  def scoped_by_product_line(scope)
    current_product_line ? scope.where(product_line: current_product_line) : scope
  end
end
