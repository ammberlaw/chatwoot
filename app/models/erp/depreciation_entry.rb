# 月度折旧计提记录：一台资产一个期间一条（唯一索引兜底，重复计提不会翻倍）。
# == Schema Information
#
# Table name: erp_depreciation_entries
#
#  id             :bigint           not null, primary key
#  amount_micros  :bigint           not null
#  period         :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  fixed_asset_id :bigint           not null
#  voucher_id     :bigint
#
# Indexes
#
#  index_erp_depreciation_entries_on_account_id                 (account_id)
#  index_erp_depreciation_entries_on_account_id_and_period      (account_id,period)
#  index_erp_depreciation_entries_on_fixed_asset_id             (fixed_asset_id)
#  index_erp_depreciation_entries_on_fixed_asset_id_and_period  (fixed_asset_id,period) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (fixed_asset_id => erp_fixed_assets.id) ON DELETE => cascade
#
class Erp::DepreciationEntry < ApplicationRecord
  belongs_to :account
  belongs_to :fixed_asset, class_name: 'Erp::FixedAsset', inverse_of: :depreciation_entries
  belongs_to :voucher, class_name: 'Erp::Voucher', optional: true

  validates :period, presence: true
  validates :amount_micros, numericality: { greater_than: 0 }
end
