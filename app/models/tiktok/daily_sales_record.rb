# TikTok 店铺每日销售明细（一店一天一行）。
# 手输 8 项；取消率/订单有效率由台数派生（不落库）；销售额换算 RMB 于录入时存快照（fx_rate + sales_amount_cny），
# 历史金额不随实时汇率波动。
# == Schema Information
#
# Table name: tiktok_daily_sales_records
#
#  id                   :bigint           not null, primary key
#  alliance_live_orders :integer          default(0), not null
#  alliance_orders      :integer          default(0), not null
#  cancelled_units      :integer          default(0), not null
#  currency             :string           default("PHP"), not null
#  fx_rate              :decimal(14, 6)   default(0.0)
#  influencer_units     :integer          default(0), not null
#  merchant_orders      :integer          default(0), not null
#  product_card_orders  :integer          default(0), not null
#  remark               :text
#  sale_date            :date             not null
#  sales_amount         :decimal(14, 2)   default(0.0)
#  sales_amount_cny     :decimal(14, 2)   default(0.0)
#  shipped_units        :integer          default(0), not null
#  total_orders         :integer          default(0), not null
#  total_units          :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  creator_id           :bigint
#  shop_id              :bigint           not null
#
# Indexes
#
#  idx_tiktok_daily_shop_date                                    (account_id,shop_id,sale_date) UNIQUE
#  index_tiktok_daily_sales_records_on_account_id_and_sale_date  (account_id,sale_date)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (creator_id => users.id) ON DELETE => nullify
#  fk_rails_...  (shop_id => tiktok_shops.id) ON DELETE => cascade
#
class Tiktok::DailySalesRecord < ApplicationRecord
  CURRENCIES = %w[USD EUR PHP CNY].freeze
  # 订单来源四拆分（看板饼图口径）：联盟直播 / 联盟 / 商品卡 / 商家。
  ORDER_SOURCE_FIELDS = %i[alliance_live_orders alliance_orders product_card_orders merchant_orders].freeze

  belongs_to :account
  belongs_to :shop, class_name: 'Tiktok::Shop'
  belongs_to :creator, class_name: 'User', optional: true

  validates :sale_date, presence: true
  validates :sale_date, uniqueness: { scope: %i[account_id shop_id], message: '该店铺当天已有记录' }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :total_orders, :total_units, :cancelled_units, :shipped_units, :influencer_units,
            *ORDER_SOURCE_FIELDS,
            numericality: { greater_than_or_equal_to: 0 }
  validates :sales_amount, numericality: { greater_than_or_equal_to: 0 }

  before_save :snapshot_cny
  before_save :sum_total_orders

  # 订单来源合计（联盟直播+联盟+商品卡+商家）。
  def order_source_total
    ORDER_SOURCE_FIELDS.sum { |field| self[field].to_i }
  end

  # 取消率 = 当天取消台数 ÷ 总台数（Excel 口径）。总台数为 0 返回 nil。
  def cancel_rate
    return nil if total_units.to_i.zero?

    (cancelled_units.to_f / total_units).round(4)
  end

  # 订单有效率 = 实发台数 ÷ 总台数。
  def valid_rate
    return nil if total_units.to_i.zero?

    (shipped_units.to_f / total_units).round(4)
  end

  private

  # 金额或币种变化（或首次）时，按当时汇率把销售额换算成 RMB 并连同汇率存快照。
  def snapshot_cny
    return unless new_record? || will_save_change_to_sales_amount? || will_save_change_to_currency?

    rate = Tiktok::CurrencyConverter.rate_to_cny(currency)
    self.fx_rate = rate
    self.sales_amount_cny = (sales_amount.to_d * rate.to_d).round(2)
  end

  # 填了订单来源拆分时，总订单以四项之和为准；存量（未拆分）记录保持原总订单不动。
  def sum_total_orders
    total = order_source_total
    self.total_orders = total if total.positive?
  end
end
