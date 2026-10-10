# 物料标准单价。财务/采购维护，给生产任务单的成本核算兜底。
#
# 取价优先级（见 Mes::MaterialPriceResolver）：
#   1. 本单采购价   —— 这张生产订单自己的采购单，真金白银，最准
#   2. 本表标准价   —— 没为这单下过采购单时用
#   3. 最近一次采购价 —— 兜底参考
# 三级都没有就留空，不填 0——少算看得见，编数看不见。
# == Schema Information
#
# Table name: mes_material_prices
#
#  id                :bigint           not null, primary key
#  remark            :text
#  unit_price_micros :bigint           default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_product_id    :bigint           not null
#  updated_by_id     :bigint
#
# Indexes
#
#  idx_mes_material_prices_on_account_product   (account_id,crm_product_id) UNIQUE
#  index_mes_material_prices_on_account_id      (account_id)
#  index_mes_material_prices_on_crm_product_id  (crm_product_id)
#  index_mes_material_prices_on_updated_by_id   (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => cascade
#  fk_rails_...  (updated_by_id => users.id) ON DELETE => nullify
#
class Mes::MaterialPrice < ApplicationRecord
  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product'
  belongs_to :updated_by, class_name: 'User', optional: true

  # 文案写死中文、不走语言文件：API 请求下 locale 实测解析不到 zh_CN，查出来是英文；
  # 全站业务校验文案（如 Mes::LineScoped 的产品线必填）都是这么写的，保持一致。
  # rubocop:disable Rails/I18nLocaleTexts
  validates :crm_product_id, uniqueness: { scope: :account_id, message: '这个物料编码已经有一条了，直接改那条' }
  # rubocop:enable Rails/I18nLocaleTexts
  validates :unit_price_micros, numericality: { greater_than_or_equal_to: 0 }
end
