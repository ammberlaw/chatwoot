class AddArrivalDateToMesPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_purchase_orders, :arrival_date, :datetime
  end
end
