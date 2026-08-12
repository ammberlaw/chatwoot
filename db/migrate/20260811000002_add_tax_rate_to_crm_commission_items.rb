class AddTaxRateToCrmCommissionItems < ActiveRecord::Migration[7.1]
  def change
    # 对公收款扣税点：每行手选增值税点(13/11)，基数 = 销售额RMB ÷ (1 + tax_rate/100)。
    # 仅在勾了「对公」时生效；默认 13。
    add_column :crm_commission_items, :tax_rate, :integer, null: false, default: 13
  end
end
