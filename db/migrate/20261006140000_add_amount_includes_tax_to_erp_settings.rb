# 销售订单金额是含税价还是不含税价——决定出库收入凭证怎么拆行：
#   含税：收入 = 金额 ÷ (1+税率)，销项税 = 金额 − 收入
#   不含税：收入 = 金额，销项税 = 金额 × 税率
# 国内合同通常报含税价，故默认 true；财务确认后在设置里切。
# 外币出口单税率 0，两种算法同值，不受影响。
class AddAmountIncludesTaxToErpSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_settings, :amount_includes_tax, :boolean, default: true, null: false
  end
end
