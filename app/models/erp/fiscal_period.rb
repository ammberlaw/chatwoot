# 会计期间：按月开闭。已结账期间内的凭证一律冻结（§13-6：新增/修改/过账/红冲/作废全禁）。
# 反结账限管理员，且留痕（reopened_at / reopened_by）。
# == Schema Information
#
# Table name: erp_fiscal_periods
#
#  id                 :bigint           not null, primary key
#  closed_at          :datetime
#  period             :string           not null
#  remark             :text
#  reopened_at        :datetime
#  status             :string           default("OPEN"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  closed_by_id       :bigint
#  closing_voucher_id :bigint
#  reopened_by_id     :bigint
#
# Indexes
#
#  index_erp_fiscal_periods_on_account_id             (account_id)
#  index_erp_fiscal_periods_on_account_id_and_period  (account_id,period) UNIQUE
#
class Erp::FiscalPeriod < ApplicationRecord
  OPEN = 'OPEN'.freeze
  CLOSED = 'CLOSED'.freeze
  STATUSES = [OPEN, CLOSED].freeze
  STATUS_LABELS = { OPEN => '未结账', CLOSED => '已结账' }.freeze

  belongs_to :account
  belongs_to :closed_by, class_name: 'User', optional: true
  belongs_to :reopened_by, class_name: 'User', optional: true
  belongs_to :closing_voucher, class_name: 'Erp::Voucher', optional: true

  validates :period, presence: true, uniqueness: { scope: :account_id }, format: { with: /\A\d{4}-\d{2}\z/ }
  validates :status, inclusion: { in: STATUSES }

  scope :closed, -> { where(status: CLOSED) }

  # 该期间是否冻结（凭证不能动）。没有记录＝从没结过账＝可动。
  def self.closed?(account, period)
    account.erp_fiscal_periods.exists?(period: period, status: CLOSED)
  end
end
