# 账套级财务政策（每账户一行）。目前承载坏账计提比例。
# == Schema Information
#
# Table name: erp_settings
#
#  id                  :bigint           not null, primary key
#  bad_debt_rates      :jsonb            not null
#  receivables_enabled :boolean          default(FALSE), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_erp_settings_on_account_id  (account_id) UNIQUE
#
class Erp::Setting < ApplicationRecord
  # 账龄段 → 计提比例（百分数）。默认值是常见做法，不是准则强制——
  # 具体比例由财务按公司会计政策定，审计要看的是「按既定政策一贯执行」。
  DEFAULT_BAD_DEBT_RATES = {
    'D30' => 0, 'D60' => 1, 'D90' => 2, 'D180' => 5, 'D365' => 10, 'OVER' => 30
  }.freeze

  belongs_to :account

  validates :account_id, uniqueness: true

  def self.for_account(account)
    find_by(account_id: account.id) || new(account: account)
  end

  # 应收台账是否已启用。过渡期账还在金蝶，这里是 false——
  # 此时销售订单「出货即完结」，不等应收收清（见 Erp::OrderCompletionService）。
  # 正式切过来那天把 erp_settings.receivables_enabled 置 true 即可，不用改代码。
  def self.receivables_enabled?(account)
    for_account(account).receivables_enabled
  end

  def bad_debt_rate_table
    DEFAULT_BAD_DEBT_RATES.merge(bad_debt_rates.presence || {})
  end
end
