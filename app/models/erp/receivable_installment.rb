# 分期收款计划：订金/尾款按约定条件到期，扫描后派生 DUE_SOON / OVERDUE 供催款提醒用。
# == Schema Information
#
# Table name: erp_receivable_installments
#
#  id            :bigint           not null, primary key
#  amount_micros :bigint           default(0), not null
#  due_basis     :string           default("FIXED"), not null
#  due_date      :date
#  due_days      :integer
#  kind          :string           default("BALANCE"), not null
#  remark        :text
#  seq           :integer          default(1), not null
#  status        :string           default("PENDING"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  receivable_id :bigint           not null
#
# Indexes
#
#  index_erp_receivable_installments_on_account_id               (account_id)
#  index_erp_receivable_installments_on_account_id_and_due_date  (account_id,due_date)
#  index_erp_receivable_installments_on_receivable_id            (receivable_id)
#
# Foreign Keys
#
#  fk_rails_...  (receivable_id => erp_receivables.id) ON DELETE => cascade
#
class Erp::ReceivableInstallment < ApplicationRecord
  KINDS = %w[DEPOSIT BALANCE OTHER].freeze
  KIND_LABELS = { 'DEPOSIT' => '订金', 'BALANCE' => '尾款', 'OTHER' => '其他' }.freeze
  DUE_BASES = %w[ORDER_DATE BEFORE_SHIPMENT AFTER_SHIPMENT BL_COPY FIXED].freeze
  DUE_BASIS_LABELS = {
    'ORDER_DATE' => '下单后N天', 'BEFORE_SHIPMENT' => '出货前', 'AFTER_SHIPMENT' => '出货后N天',
    'BL_COPY' => '见提单副本', 'FIXED' => '指定日期'
  }.freeze
  STATUSES = %w[PENDING DUE_SOON OVERDUE SETTLED].freeze
  STATUS_LABELS = { 'PENDING' => '未到期', 'DUE_SOON' => '即将到期', 'OVERDUE' => '已逾期', 'SETTLED' => '已结清' }.freeze

  DUE_SOON_DAYS = 7

  belongs_to :account
  belongs_to :receivable, class_name: 'Erp::Receivable', inverse_of: :installments

  validates :kind, inclusion: { in: KINDS }
  validates :due_basis, inclusion: { in: DUE_BASES }
  validates :amount_micros, numericality: { greater_than: 0 }

  before_validation :inherit_account

  # 台账收清后分期一律 SETTLED；否则按到期日派生（实时算，不落状态）。
  def derived_status(today = Time.zone.today)
    return 'SETTLED' if receivable.derived_status == Erp::Receivable::PAID
    return 'PENDING' if due_date.blank?
    return 'OVERDUE' if due_date < today
    return 'DUE_SOON' if due_date <= today + DUE_SOON_DAYS

    'PENDING'
  end

  private

  def inherit_account
    self.account_id ||= receivable&.account_id
  end
end
