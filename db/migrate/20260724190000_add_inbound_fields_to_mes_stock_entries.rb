class AddInboundFieldsToMesStockEntries < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_stock_entries, :actual_inbound_date, :datetime
    add_column :mes_stock_entries, :color, :string
  end
end
