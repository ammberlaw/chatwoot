class AddDeliveryDateToMesPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_purchase_orders, :delivery_date, :date
  end
end
