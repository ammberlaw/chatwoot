# 考核指标（考核方案的子项，可增删改）。对应 A-CRM(Twenty) schemeItem。
# data_source 决定二期打分是否给系统建议分：CRM_SALES/CRM_NEWCUST 自动带完成率算分，
# MANUAL/MANAGER 由人填。baseline_value/target_value 用文本（有「≥6%」「三项合规」等非数值）。
# == Schema Information
#
# Table name: crm_scheme_items
#
#  id                :bigint           not null, primary key
#  baseline_value    :string
#  data_source       :string           default("MANUAL"), not null
#  dimension         :string
#  name              :string           not null
#  sort_order        :integer          default(0)
#  standard          :text
#  target_value      :string
#  weight            :decimal(5, 1)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_kpi_scheme_id :bigint           not null
#
# Indexes
#
#  index_crm_scheme_items_on_account_id         (account_id)
#  index_crm_scheme_items_on_crm_kpi_scheme_id  (crm_kpi_scheme_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_kpi_scheme_id => crm_kpi_schemes.id) ON DELETE => cascade
#
class Crm::SchemeItem < ApplicationRecord
  DATA_SOURCES = %w[CRM_SALES CRM_NEWCUST MANUAL MANAGER].freeze

  belongs_to :account
  belongs_to :scheme, class_name: 'Crm::KpiScheme', foreign_key: :crm_kpi_scheme_id, inverse_of: :scheme_items

  validates :name, presence: true
  validates :data_source, inclusion: { in: DATA_SOURCES }

  # 经方案嵌套创建时自动继承 account。
  before_validation { self.account_id ||= scheme&.account_id }

  scope :ordered, -> { order(:sort_order, :id) }
end
