class Crm::SalesOrderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def parse_pi?
    true
  end

  def update?
    true
  end

  def attach?
    true
  end

  def detach?
    true
  end

  def audits?
    true
  end

  # 转单预览（明细匹配产品档案）：与看订单同权，不下发成本价等敏感字段。
  def convert_preview?
    true
  end

  # 回款进度（只读）：与看订单同权——订单可见性本身就是边界，且只透出回款，不含成本/毛利。
  def receivable_progress?
    true
  end

  # 生产追溯：与看订单同权限（数据本身已按订单可见范围收口）。
  def production_trace?
    true
  end

  # 转 ERP 预检（只读）：与看订单同权。只输出单据字段与缺失项，不含成本/毛利。
  def erp_export?
    true
  end

  # 删除（软删进回收箱）：负责人本人 或 管理员/副管。具体归属在控制器 can_delete_order? 把关。
  def destroy?
    true
  end

  # 回收箱（列表 + 恢复）：仅管理员/副管理员，避免业务员自行捞回引发矛盾。
  # 录单的收款账户下拉（只给 id + 名字）：凡是能建单的都要选，不另设门槛。
  def receipt_accounts?
    true
  end

  def deleted?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end

  def restore?
    deleted?
  end
end

Crm::SalesOrderPolicy.prepend_mod_with('Crm::SalesOrderPolicy')
