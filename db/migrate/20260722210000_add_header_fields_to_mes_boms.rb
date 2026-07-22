class AddHeaderFieldsToMesBoms < ActiveRecord::Migration[7.1]
  def change
    change_table :mes_boms, bulk: true do |t|
      t.date :submit_date          # 投单日期
      t.string :doc_no             # 投单单号（如 WT20260605-01）
      t.string :customer_name      # 客户 / 项目名称
      t.string :model              # 型号（自由文本，含客户定制说明）
      t.string :product_code       # 产成品代码（如 P.01.842，供 ERP 共享）
      t.integer :order_qty         # 投单数量（台）
      t.string :bare_color         # 裸机颜色
      t.string :case_color         # 皮套颜色
    end
  end
end
