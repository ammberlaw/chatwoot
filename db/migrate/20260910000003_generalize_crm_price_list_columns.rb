# 核价表改成「自定义列」结构。
# 起因：各产品线的表长得完全不一样——平板是 型号/规格 + 三档量价；D、L 系列是
# 款式/尺寸/型号/CPU/系统/配置 + 三档；水牌机干脆不按数量分档，而是按触摸类型
# （广告机款/红外/电容/纳米/镜面…）横向列价；背包屏还多出「带触摸加价/亮度加价/电池加价」几列。
# 写死「型号+规格+N 档价」装不下，改成每张表自己定义列（label + type），
# 明细行按列顺序存值。type=price 的列右对齐并带币种符号，其余按文本。
class GeneralizeCrmPriceListColumns < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_price_lists, :columns, :jsonb, null: false, default: []
    add_column :crm_price_list_items, :values, :jsonb, null: false, default: []
    # 旧结构（仅 dev 有几条试验数据，生产未上线）不再使用。
    remove_column :crm_price_lists, :tier_labels
    remove_column :crm_price_list_items, :model
    remove_column :crm_price_list_items, :spec
    remove_column :crm_price_list_items, :prices
  end

  def down
    remove_column :crm_price_lists, :columns
    remove_column :crm_price_list_items, :values
    add_column :crm_price_lists, :tier_labels, :string, array: true, default: []
    add_column :crm_price_list_items, :model, :string
    add_column :crm_price_list_items, :spec, :text
    add_column :crm_price_list_items, :prices, :decimal, precision: 12, scale: 2, array: true, default: []
  end
end
