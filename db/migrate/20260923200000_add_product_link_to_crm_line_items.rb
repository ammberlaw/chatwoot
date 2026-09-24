# 产品档案关联下沉到明细行。
#
# 为什么要做：业务员在金蝶下单本来就要选产品，这边却是抄 PI 的自由文本，
# 于是转单去 MES/ERP 时 89% 的明细行要重新人工匹配一次（近 60 天 199 行只有 22 行能自动带出）。
# 关联一次、全链路继承，成本归集与毛利也才算得准。
#
# PI 明细也要加：近 90 天 39% 的销售订单是 PI 付款后自动生成的，
# 只在销售订单上加的话，这部分订单的产品信息在源头就已经丢了。
class AddProductLinkToCrmLineItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :crm_pi_items, :crm_product, null: true, foreign_key: { to_table: :crm_products, on_delete: :nullify },
                                               index: true

    # 收款方式：做成可自己维护的下拉（crm_option_items 的 payment_term 类别），这里存选项 code。
    add_column :crm_sales_orders, :payment_term, :string
  end
end
