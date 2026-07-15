# 考核表行（个人考核表的子项）：从方案指标复制而来，加「完成值/得分/建议分」。
# == Schema Information
#
# Table name: crm_kpi_sheet_items
#
#  id               :bigint           not null, primary key
#  actual_value     :string
#  baseline_value   :string
#  data_source      :string           default("MANUAL"), not null
#  dimension        :string
#  name             :string           not null
#  score            :decimal(7, 2)
#  sort_order       :integer          default(0)
#  standard         :text
#  suggested_score  :decimal(7, 2)
#  target_value     :string
#  weight           :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  crm_kpi_sheet_id :bigint           not null
#
# Indexes
#
#  index_crm_kpi_sheet_items_on_account_id        (account_id)
#  index_crm_kpi_sheet_items_on_crm_kpi_sheet_id  (crm_kpi_sheet_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_kpi_sheet_id => crm_kpi_sheets.id) ON DELETE => cascade
#
class Crm::KpiSheetItem < ApplicationRecord
  belongs_to :account
  belongs_to :sheet, class_name: 'Crm::KpiSheet', foreign_key: :crm_kpi_sheet_id, inverse_of: :sheet_items

  validates :name, presence: true

  before_validation { self.account_id ||= sheet&.account_id }

  scope :ordered, -> { order(:sort_order, :id) }
end
