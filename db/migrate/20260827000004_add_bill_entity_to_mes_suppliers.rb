# 供应商开票主体/税模式：决定按供应商拆单导出时套哪个采购单模板。
# wintouch=联合触控（未税单）；liontek=联迪（含税单，单价×1.13）。默认 wintouch。
class AddBillEntityToMesSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_suppliers, :bill_entity, :string, default: 'wintouch', null: false
  end
end
