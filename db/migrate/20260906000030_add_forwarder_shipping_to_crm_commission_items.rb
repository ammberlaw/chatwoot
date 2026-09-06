class AddForwarderShippingToCrmCommissionItems < ActiveRecord::Migration[7.1]
  def change
    # 货代实收运费：记录货代实际收取的运费（微分存储），只作参考列展示，不参与提成折算。
    add_column :crm_commission_items, :forwarder_shipping_micros, :bigint
  end
end
