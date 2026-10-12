# 应付台账按月、按对公/对私统计所需的两件东西：
#   settle_type  钱打到公司账户（有票、含税）还是个人账户（无票、未税）；
#   incurred_on  这笔欠款算在哪一天——按货到（入库）日期，不是财务什么时候录的。
# 同一家供应商两种结算都有，所以标记落在单据上；供应商档案只存默认值，下单带出、个别单可改。
class AddSettleTypeForPayables < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_suppliers, :default_settle_type, :string, null: false, default: 'PUBLIC'
    add_column :mes_purchase_orders, :settle_type, :string
    # 不另建索引：应付台账统共几十条，全表扫比维护索引划算。
    add_column :erp_payables, :settle_type, :string, null: false, default: 'PUBLIC'
    add_column :erp_payables, :incurred_on, :date
  end
end
