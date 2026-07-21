# 质量检验记录（数量口径，SN 单件追溯后期）：IQC来料/IPQC过程/FQC成品/AGING老化。
class Mes::Inspection < ApplicationRecord
  KINDS = %w[IQC IPQC FQC AGING].freeze
  RESULTS = %w[PASS FAIL CONDITIONAL].freeze

  belongs_to :account
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', optional: true
  belongs_to :inspector, class_name: 'User', optional: true

  before_validation :stamp_inspected_at, on: :create
  before_validation :derive_result

  validates :kind, inclusion: { in: KINDS }
  validates :result, inclusion: { in: RESULTS }, allow_blank: true
  validates :inspected_qty, :passed_qty, :failed_qty, numericality: { greater_than_or_equal_to: 0 }

  scope :this_month, -> { where(inspected_at: Time.current.beginning_of_month..Time.current.end_of_month) }

  private

  def stamp_inspected_at
    self.inspected_at ||= Time.current
  end

  # 未显式给结果时按不良数推断。
  def derive_result
    return if result.present?

    self.result = if failed_qty.to_d.zero?
                    'PASS'
                  elsif passed_qty.to_d.zero?
                    'FAIL'
                  else
                    'CONDITIONAL'
                  end
  end
end
