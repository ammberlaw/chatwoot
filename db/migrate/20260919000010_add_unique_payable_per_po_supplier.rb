class AddUniquePayablePerPoSupplier < ActiveRecord::Migration[7.1]
  # 按采购单建应付是「每供应商一条」：应用层查过一遍再建，但并发双击两边都读到空、各建一条。
  # 手工应付（不挂采购单）不受限。
  def change
    add_index :erp_payables, [:account_id, :mes_purchase_order_id, :mes_supplier_id],
              unique: true, where: 'mes_purchase_order_id IS NOT NULL',
              name: 'uniq_erp_payable_po_supplier'
  end
end
