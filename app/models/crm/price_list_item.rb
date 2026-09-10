# 核价表的一行：values 按所属版本 columns 的顺序存值（第 n 个值 = 第 n 列）。
# == Schema Information
#
# Table name: crm_price_list_items
#
#  id                :bigint           not null, primary key
#  position          :integer          default(0), not null
#  remark            :string
#  values            :jsonb            not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_price_list_id :bigint           not null
#
# Indexes
#
#  index_crm_price_list_items_on_list_position  (crm_price_list_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (crm_price_list_id => crm_price_lists.id) ON DELETE => cascade
#
class Crm::PriceListItem < ApplicationRecord
  self.table_name = 'crm_price_list_items'

  # 产品图：核价表里认产品全靠图，型号名看不出长什么样。
  # 一行一张（Excel 里同一行挂多张时取第一张）。
  has_one_attached :image

  belongs_to :account
  belongs_to :price_list, class_name: 'Crm::PriceList', foreign_key: :crm_price_list_id, inverse_of: :items

  scope :ordered, -> { order(:position, :id) }
end
