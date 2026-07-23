class AddItemTypeAndProductToMesPurchaseItems < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_purchase_items, :item_type, :string, null: false, default: 'MATERIAL'
    add_reference :mes_purchase_items, :crm_product, null: true, foreign_key: { on_delete: :nullify }
  end
end
