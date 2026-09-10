# TK 支出台账：一笔店铺运营或部门日常开销。部门必填、店铺选填（人员日结/办公这类不挂店铺）。
# 与 CRM 备用金台账互不重叠——TK 的支出在这里记。
# == Schema Information
#
# Table name: tiktok_expenses
#
#  id            :bigint           not null, primary key
#  amount        :decimal(14, 2)   default(0.0), not null
#  amount_cny    :decimal(14, 2)   default(0.0), not null
#  category      :string           not null
#  currency      :string           default("CNY"), not null
#  expense_date  :date             not null
#  fx_rate       :decimal(14, 6)   default(0.0), not null
#  remark        :text
#  subject       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  creator_id    :bigint
#  department_id :bigint           not null
#  shop_id       :bigint
#
# Indexes
#
#  index_tiktok_expenses_on_account_and_shop  (account_id,shop_id)
#  index_tiktok_expenses_on_dept_and_date     (account_id,department_id,expense_date)
#
class Tiktok::Expense < ApplicationRecord
  self.table_name = 'tiktok_expenses'

  CATEGORIES = %w[广告花费 物流费 海外仓费用 退货损耗 达人合作 平台费用
                  人员费用 办公用品 设备采购 其它].freeze
  CURRENCIES = %w[CNY PHP USD EUR].freeze

  belongs_to :account
  belongs_to :department, class_name: 'Tiktok::Department'
  belongs_to :shop, class_name: 'Tiktok::Shop', optional: true
  belongs_to :creator, class_name: 'User', optional: true

  # 票据/截图选填（广告后台截图、收据照片…）。
  has_many_attached :files

  validates :expense_date, :category, :subject, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :amount, numericality: { greater_than: 0 }

  before_save :snapshot_cny

  scope :in_month, ->(month) { where(expense_date: Date.parse("#{month}-01")..Date.parse("#{month}-01").end_of_month) }
  scope :ordered, -> { order(expense_date: :desc, id: :desc) }

  private

  # 与利润表同款：金额或币种变动时快照当时汇率，RMB 金额落库，事后汇率变动不改历史账。
  def snapshot_cny
    return unless new_record? || will_save_change_to_amount? || will_save_change_to_currency?

    rate = Tiktok::CurrencyConverter.rate_to_cny(currency)
    self.fx_rate = rate
    self.amount_cny = (amount.to_d * rate.to_d).round(2)
  end
end
