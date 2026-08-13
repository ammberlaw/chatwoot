class AddSalesOrderLinkFieldsToMes < ActiveRecord::Migration[7.1]
  def change
    # 业务员建生产订单须关联 CRM 销售订单并带出 PI 号 + 从 CRM 客户带出国家。
    # crm_sales_orders.pi_no 在生产分支（含 PI 模块）已存在；此处守卫，生产上跳过、开发库补齐。
    add_column :crm_sales_orders, :pi_no, :string unless column_exists?(:crm_sales_orders, :pi_no)

    # 生产订单挂 CRM 客户（国家从 crm_customers.trade_country 派生，不另存快照列）。
    unless column_exists?(:mes_production_orders, :crm_customer_id)
      add_reference :mes_production_orders, :crm_customer, null: true, index: true
    end
  end
end
