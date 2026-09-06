# 固定资产：直线法折旧（原值 × (1-残值率) / 折旧月数），按月计提。
# 累计折旧只由计提/处置代码路径维护，不接受手工改。
# == Schema Information
#
# Table name: erp_fixed_assets
#
#  id                              :bigint           not null, primary key
#  accumulated_depreciation_micros :bigint           default(0), not null
#  asset_no                        :string           not null
#  category                        :string           default("EQUIPMENT"), not null
#  disposal_income_micros          :bigint           default(0), not null
#  disposed_at                     :date
#  name                            :string           not null
#  original_value_micros           :bigint           not null
#  purchased_at                    :date             not null
#  remark                          :text
#  residual_rate                   :decimal(5, 2)    default(5.0), not null
#  status                          :string           default("IN_USE"), not null
#  useful_months                   :integer          default(60), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  account_id                      :bigint           not null
#  department_id                   :bigint
#  keeper_id                       :bigint
#
# Indexes
#
#  index_erp_fixed_assets_on_account_id               (account_id)
#  index_erp_fixed_assets_on_account_id_and_asset_no  (account_id,asset_no) UNIQUE
#  index_erp_fixed_assets_on_account_id_and_status    (account_id,status)
#
class Erp::FixedAsset < ApplicationRecord
  IN_USE = 'IN_USE'.freeze
  DISPOSED = 'DISPOSED'.freeze
  SCRAPPED = 'SCRAPPED'.freeze
  STATUSES = [IN_USE, DISPOSED, SCRAPPED].freeze
  STATUS_LABELS = { IN_USE => '在用', DISPOSED => '已处置', SCRAPPED => '已报废' }.freeze

  CATEGORIES = %w[EQUIPMENT VEHICLE ELECTRONIC OFFICE OTHER].freeze
  CATEGORY_LABELS = {
    'EQUIPMENT' => '生产设备', 'VEHICLE' => '车辆', 'ELECTRONIC' => '电子设备',
    'OFFICE' => '办公家具', 'OTHER' => '其他'
  }.freeze

  belongs_to :account
  belongs_to :department, class_name: 'Org::Department', optional: true
  belongs_to :keeper, class_name: 'User', optional: true
  has_many :depreciation_entries, -> { order(period: :desc) }, class_name: 'Erp::DepreciationEntry',
                                                               foreign_key: :fixed_asset_id,
                                                               dependent: :destroy, inverse_of: :fixed_asset

  validates :asset_no, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :original_value_micros, numericality: { greater_than: 0 }
  validates :useful_months, numericality: { greater_than: 0 }

  before_validation :assign_asset_no, on: :create

  scope :in_use, -> { where(status: IN_USE) }

  # 可折旧总额 = 原值 - 残值。
  def depreciable_micros
    (original_value_micros * (1 - (residual_rate.to_d / 100))).round
  end

  # 直线法月折旧额。
  def monthly_depreciation_micros
    (depreciable_micros / useful_months.to_d).round
  end

  # 还能计提多少（提到残值为止，最后一个月自动补差额）。
  def remaining_depreciable_micros
    [depreciable_micros - accumulated_depreciation_micros, 0].max
  end

  def net_value_micros
    original_value_micros - accumulated_depreciation_micros
  end

  private

  def assign_asset_no
    return if asset_no.present?

    self.asset_no = Erp::DocumentNumber.next(account, 'FA', :erp_fixed_assets, :asset_no)
  end
end
