# TikTok 板块店铺（录入下拉的数据源）。管理员/副管理员在「店铺设置」维护。
# 停用（active=false）后不再出现在录入下拉，但保留历史销售记录。
# == Schema Information
#
# Table name: tiktok_shops
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  region        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  department_id :bigint
#
# Indexes
#
#  idx_tiktok_shops_name                          (account_id,name) UNIQUE
#  index_tiktok_shops_on_account_id_and_position  (account_id,position)
#  index_tiktok_shops_on_department_id            (department_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (department_id => tiktok_departments.id) ON DELETE => nullify
#
class Tiktok::Shop < ApplicationRecord
  # 首访播种的默认店铺（现有两家）。
  DEFAULTS = ['KidzTab PH', 'TotsTech PH'].freeze

  belongs_to :account
  belongs_to :department, class_name: 'Tiktok::Department', optional: true
  has_many :daily_sales_records, class_name: 'Tiktok::DailySalesRecord', dependent: :restrict_with_error
  has_many :profit_records, class_name: 'Tiktok::ProfitRecord', dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # 该账号无店铺时播种默认两家。并发下靠唯一索引兜底。
  def self.ensure_defaults!(account)
    return if where(account_id: account.id).exists?

    DEFAULTS.each_with_index do |name, index|
      create!(account: account, name: name, position: index)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
