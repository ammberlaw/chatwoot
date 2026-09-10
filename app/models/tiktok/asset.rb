# TK 固定资产登记：拍摄设备/电脑/手机/灯光等，只登记「有什么、谁在用、在哪、多少钱」，
# 不算折旧——折旧归 ERP 的固定资产模块（字段留够，将来可对接过去）。
# == Schema Information
#
# Table name: tiktok_assets
#
#  id            :bigint           not null, primary key
#  amount        :decimal(14, 2)   default(0.0), not null
#  category      :string
#  code          :string
#  location      :string
#  name          :string           not null
#  purchased_on  :date
#  remark        :text
#  status        :string           default("IN_USE"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  creator_id    :bigint
#  department_id :bigint           not null
#  holder_id     :bigint
#
# Indexes
#
#  index_tiktok_assets_on_account_and_code  (account_id,code)
#  index_tiktok_assets_on_account_and_dept  (account_id,department_id)
#
class Tiktok::Asset < ApplicationRecord
  self.table_name = 'tiktok_assets'

  CATEGORIES = %w[拍摄设备 电脑 手机 灯光音响 家具 样机 其它].freeze
  STATUSES = { 'IN_USE' => '在用', 'IDLE' => '闲置', 'REPAIR' => '维修中', 'SCRAPPED' => '已报废' }.freeze

  belongs_to :account
  belongs_to :department, class_name: 'Tiktok::Department'
  belongs_to :holder, class_name: 'User', optional: true
  belongs_to :creator, class_name: 'User', optional: true

  has_many_attached :files

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(status: :asc, purchased_on: :desc, id: :desc) }

  def status_label = STATUSES[status]
end
