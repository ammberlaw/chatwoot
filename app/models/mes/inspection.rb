# 质量检验记录（数量口径，SN 单件追溯后期）：IQC来料/IPQC过程/FQC成品/AGING老化。
# == Schema Information
#
# Table name: mes_inspections
#
#  id                  :bigint           not null, primary key
#  defect_reason       :text
#  failed_qty          :decimal(14, 3)   default(0.0), not null
#  inspected_at        :datetime
#  inspected_qty       :decimal(14, 3)   default(0.0), not null
#  item_type           :string
#  kind                :string           not null
#  need_rework         :boolean          default(FALSE), not null
#  passed_qty          :decimal(14, 3)   default(0.0), not null
#  product_line        :string
#  remark              :text
#  result              :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_product_id      :bigint
#  inspector_id        :bigint
#  mes_material_id     :bigint
#  production_order_id :bigint
#  purchase_order_id   :bigint
#
# Indexes
#
#  index_mes_inspections_on_account_and_product_line  (account_id,product_line)
#  index_mes_inspections_on_account_id                (account_id)
#  index_mes_inspections_on_account_id_and_kind       (account_id,kind)
#  index_mes_inspections_on_crm_product_id            (crm_product_id)
#  index_mes_inspections_on_mes_material_id           (mes_material_id)
#  index_mes_inspections_on_production_order_id       (production_order_id)
#  index_mes_inspections_on_purchase_order_id         (purchase_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (inspector_id => users.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => nullify
#
class Mes::Inspection < ApplicationRecord
  include Mes::LineScoped

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

  def product_line_source = production_order || purchase_order || crm_product || mes_material

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
