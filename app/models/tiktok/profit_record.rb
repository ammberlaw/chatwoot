# TikTok 出库利润表：按 店铺 × 产品型号 × 统计月份 一行。负责人每月填，系统自动算毛利/净利润。
# 成本/佣金/税费/其它成本均为 CNY 直填；已入账金额按币种换算 RMB 存快照。
# == Schema Information
#
# Table name: tiktok_profit_records
#
#  id                    :bigint           not null, primary key
#  cost_unit_price       :decimal(14, 2)   default(0.0)
#  currency              :string           default("PHP"), not null
#  extra_expenses        :jsonb            not null
#  fx_rate               :decimal(14, 6)   default(0.0)
#  influencer_commission :decimal(14, 2)   default(0.0)
#  other_cost            :decimal(14, 2)   default(0.0)
#  other_cost_note       :text
#  period_note           :string
#  platform_commission   :decimal(14, 2)   default(0.0)
#  platform_negative     :integer          default(0), not null
#  product_model         :string           not null
#  recorded_amount       :decimal(14, 2)   default(0.0)
#  recorded_amount_cny   :decimal(14, 2)   default(0.0)
#  recorded_quantity     :integer          default(0), not null
#  stat_month            :string           not null
#  tax                   :decimal(14, 2)   default(0.0)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  creator_id            :bigint
#  shop_id               :bigint           not null
#
# Indexes
#
#  idx_tiktok_profit_uniq                                    (account_id,shop_id,stat_month,product_model) UNIQUE
#  index_tiktok_profit_records_on_account_id_and_stat_month  (account_id,stat_month)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (creator_id => users.id) ON DELETE => nullify
#  fk_rails_...  (shop_id => tiktok_shops.id) ON DELETE => cascade
#
class Tiktok::ProfitRecord < ApplicationRecord
  CURRENCIES = %w[USD EUR PHP CNY].freeze

  belongs_to :account
  belongs_to :shop, class_name: 'Tiktok::Shop'
  belongs_to :creator, class_name: 'User', optional: true

  validates :product_model, presence: true
  validates :stat_month, presence: true, format: { with: /\A\d{4}-\d{2}\z/, message: '须为 YYYY-MM' }
  validates :stat_month, uniqueness: { scope: %i[account_id shop_id product_model], message: '该店铺该型号当月已有记录' }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :recorded_quantity, :platform_negative, numericality: { greater_than_or_equal_to: 0 }

  before_save :snapshot_cny

  # 售出产品总成本 = 出厂成本单价 × 已入账数量
  def total_cost
    (cost_unit_price.to_d * recorded_quantity.to_i).round(2)
  end

  # 产品总毛利润 = 已入账金额(RMB) − 售出总成本
  def gross_profit
    (recorded_amount_cny.to_d - total_cost).round(2)
  end

  # 平均单台毛利 = 总毛利 ÷ 数量
  def avg_unit_profit
    return nil if recorded_quantity.to_i.zero?

    (gross_profit / recorded_quantity).round(2)
  end

  # 平均售卖单价 = 已入账金额(RMB) ÷ 数量
  def avg_sell_price
    return nil if recorded_quantity.to_i.zero?

    (recorded_amount_cny.to_d / recorded_quantity).round(2)
  end

  # 其它费用合计（广告花费 / 海外仓费用 等自定义项）。
  def extra_expenses_total
    Array(extra_expenses).sum { |e| e['amount'].to_d }
  end

  # 净利润 = 总毛利 − 达人佣金 − 平台佣金 − 税费 − 其它成本 − 其它费用合计
  def net_profit
    (gross_profit - influencer_commission.to_d - platform_commission.to_d - tax.to_d -
      other_cost.to_d - extra_expenses_total).round(2)
  end

  private

  def snapshot_cny
    return unless new_record? || will_save_change_to_recorded_amount? || will_save_change_to_currency?

    rate = Tiktok::CurrencyConverter.rate_to_cny(currency)
    self.fx_rate = rate
    self.recorded_amount_cny = (recorded_amount.to_d * rate.to_d).round(2)
  end
end
