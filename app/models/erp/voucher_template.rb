# 凭证模板：把每月重复的分录（计提工资、房租水电、折旧摊销…）存成模板，新建凭证时一键带出。
# 模板只是录入草稿，不参与记账，所以分录直接存 jsonb，不进 erp_voucher_lines。
# == Schema Information
#
# Table name: erp_voucher_templates
#
#  id            :bigint           not null, primary key
#  lines         :jsonb            not null
#  name          :string           not null
#  summary       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_erp_voucher_templates_on_account_id           (account_id)
#  index_erp_voucher_templates_on_account_id_and_name  (account_id,name) UNIQUE
#
class Erp::VoucherTemplate < ApplicationRecord
  # 模板分录里允许保留的字段（金额可留空，用的时候再填）。
  LINE_KEYS = %w[
    ledger_account_id direction amount_micros summary currency exchange_rate
    crm_customer_id mes_supplier_id crm_sales_order_id department_id member_id cash_flow_item
  ].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validate :validate_lines

  before_validation :sanitize_lines

  private

  def sanitize_lines
    self.lines = Array(lines).map { |line| line.to_h.stringify_keys.slice(*LINE_KEYS) }
  end

  def validate_lines
    errors.add(:lines, '模板至少要有两行分录') if Array(lines).size < 2
    return if Array(lines).all? { |line| line['ledger_account_id'].present? }

    errors.add(:lines, '每行都要选会计科目')
  end
end
