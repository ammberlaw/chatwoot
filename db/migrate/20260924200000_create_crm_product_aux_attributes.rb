# 辅助属性：同一个物料编码下的多个可选变体。
#
# 现状是把它塞在产品备注里（「常规线长；辅助属性管理：是」这种），
# 于是下单选料时只能靠人读备注再手写，核对不了、也统计不了。
#
# 金蝶那边的形态是：P.07.009（327090电池）下挂 P.07.009_001 喷码6000 /
# _002 喷码3500 / _003 喷码4000…，开单时在「辅助属性」列里单选一个。
# 这里照同一口径建档：编码按 <物料编码>_<三位序号> 自动生成，省得人工编。
#
# 命名避开 attributes：ActiveRecord 自带 #attributes，叫 aux_attributes 才不打架。
class CreateCrmProductAuxAttributes < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_product_aux_attributes do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :crm_product, null: false, index: { name: 'idx_crm_aux_attrs_on_product' },
                                 foreign_key: { to_table: :crm_products, on_delete: :cascade }
      t.string :code, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      # 停用而非删除：历史单据上已经选过的属性不能凭空消失。
      t.boolean :is_active, null: false, default: true
      t.timestamps
    end

    add_index :crm_product_aux_attributes, [:account_id, :code], unique: true,
                                                                 name: 'idx_crm_aux_attrs_unique_code'

    # BOM 明细选中的那一个。带上名称快照：属性以后改名或停用，
    # 已下发的 BOM 上还得显示当时选的是什么。
    add_reference :mes_bom_items, :crm_product_aux_attribute, null: true,
                                                              index: { name: 'idx_mes_bom_items_on_aux_attr' },
                                                              foreign_key: { to_table: :crm_product_aux_attributes,
                                                                             on_delete: :nullify }
    add_column :mes_bom_items, :aux_attribute_name, :string
  end
end
