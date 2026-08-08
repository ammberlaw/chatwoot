# 中国银行现汇买入价快照（折算汇率）。每日由 Crm::FxRateSyncJob 抓取入库，
# 外币销售订单建单时锁定「做单当日」汇率，看板据此折算人民币。
# == Schema Information
#
# Table name: crm_fx_rates
#
#  id           :bigint           not null, primary key
#  currency     :string           not null
#  published_at :datetime
#  quote_date   :date             not null
#  rate         :decimal(16, 6)   not null
#  source       :string           default("BOC"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_crm_fx_rates_on_currency_and_quote_date  (currency,quote_date) UNIQUE
#
class Crm::FxRate < ApplicationRecord
  validates :currency, presence: true
  validates :quote_date, presence: true
  validates :rate, presence: true, numericality: { greater_than: 0 }
  validates :currency, uniqueness: { scope: :quote_date }

  # 指定币种在给定日期（含）之前最近一个牌价的折算汇率（CNY / 1 单位）。
  # CNY 恒为 1；查不到返回 nil（调用方决定兜底：留空手填 / 不换算）。
  def self.rate_for(currency, date)
    return 1.0 if currency.blank? || currency == 'CNY'
    return nil if date.blank?

    where(currency: currency).where('quote_date <= ?', date)
                             .order(quote_date: :desc).limit(1).pick(:rate)&.to_f
  end
end
