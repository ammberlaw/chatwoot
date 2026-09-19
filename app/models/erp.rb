module Erp
  def self.table_name_prefix
    'erp_'
  end

  # 生产总开关：ERP 未上线/未平行对账期间全局关（默认关）。关时侧栏、API、
  # 以及 CRM 订单页的回款进度条一律当 ERP 不存在。开发栈设 ERP_ENABLED=true。
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('ERP_ENABLED', false))
  end
end
