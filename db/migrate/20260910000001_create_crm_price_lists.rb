# 核价表（内部报价单）：主管/财务按版本维护阶梯价，业务员只读最新已发布版。
# 按「版本」而非「单条价格」建模——业务上每次调价都是整张表重发一版（原 Excel 十个 sheet
# 就是十个版本），事后查「当时报的是哪个价」也只能靠版本。
class CreateCrmPriceLists < ActiveRecord::Migration[7.1]
  def change
    create_lists
    create_items
  end

  private

  def create_lists
    create_table :crm_price_lists do |t|
      t.bigint :account_id, null: false
      t.string :title, null: false                       # 外贸平板内部报价单
      t.date :effective_on                               # 落款日期 = 该版生效日
      t.string :currency, null: false, default: 'USD'
      t.string :status, null: false, default: 'DRAFT'    # DRAFT / PUBLISHED / ARCHIVED
      t.string :tier_labels, array: true, default: []    # ['10-100','100-500','500-1000']
      t.text :header_note                                # 表头备注（英规充电器加价等）
      t.text :rules_note                                 # 报价规则说明
      t.string :footer_name                              # 东莞市联迪科技有限公司平板部
      t.bigint :creator_id
      t.bigint :published_by_id
      t.datetime :published_at
      t.timestamps
    end
    add_index :crm_price_lists, %i[account_id status effective_on],
              name: 'index_crm_price_lists_on_account_status_date'
  end

  def create_items
    create_table :crm_price_list_items do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_price_list_id, null: false
      t.integer :position, null: false, default: 0
      t.string :model, null: false                       # 型号 K705A
      t.text :spec                                       # 产品规格（含「含皮套」「库存价格」等说明）
      t.decimal :prices, precision: 12, scale: 2, array: true, default: [] # 与 tier_labels 一一对应
      t.string :remark
      t.timestamps
    end
    add_index :crm_price_list_items, %i[crm_price_list_id position],
              name: 'index_crm_price_list_items_on_list_position'
    add_foreign_key :crm_price_list_items, :crm_price_lists, column: :crm_price_list_id, on_delete: :cascade
  end
end
