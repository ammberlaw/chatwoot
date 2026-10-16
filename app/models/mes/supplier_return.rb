# 退料返修单：把料退给供应商修，修好再回来。
#
# 用户原话：「我这边退料出去，多久能回来？是不是要设置一个退出去的时间跟物料返修回来时间呢」
# 所以这张单的重点不是数量，是**两个时间**和中间这段在外面的天数。
#
# ⚠️ 本期只记台账、不动库存：返修回来要不要重新入库、要不要质检还没定（用户标「待确认」）。
# 真要接库存时，按明细行补入库单即可——行上已经记了产品档案 id 和已返回数量。
# == Schema Information
#
# Table name: mes_supplier_returns
#
#  id                  :bigint           not null, primary key
#  product_line        :string
#  reason              :text
#  remark              :text
#  return_no           :string           not null
#  returned_on         :date
#  sent_on             :date
#  status              :string           default("DRAFT"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  mes_supplier_id     :bigint           not null
#  owner_id            :bigint
#  production_order_id :bigint
#
# Indexes
#
#  index_mes_supplier_returns_on_account_id_and_return_no  (account_id,return_no) UNIQUE
#  index_mes_supplier_returns_on_account_id_and_status     (account_id,status)
#  index_mes_supplier_returns_on_production_order_id       (production_order_id)
#
class Mes::SupplierReturn < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  STATUS_LABELS = {
    'DRAFT' => '草稿',
    'SENT' => '已退出',
    'PARTIAL' => '部分返回',
    'RETURNED' => '已返回',
    'CLOSED' => '已关闭'
  }.freeze
  STATUSES = STATUS_LABELS.keys.freeze

  belongs_to :account
  belongs_to :mes_supplier, class_name: 'Mes::Supplier'
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :items, class_name: 'Mes::SupplierReturnItem', dependent: :destroy, inverse_of: :supplier_return
  accepts_nested_attributes_for :items, allow_destroy: true

  validates :return_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  before_validation :inherit_account_on_items

  def self.document_number_prefix = 'RT'
  def self.document_number_column = :return_no

  def status_label = STATUS_LABELS[status]

  # 退出去多少天了 / 这趟来回走了多少天——用户要的就是这个数。
  def days_out
    return nil if sent_on.blank?

    ((returned_on || Date.current) - sent_on).to_i
  end

  def out? = sent_on.present? && returned_on.blank?

  # 退出 → 记日期、进「已退出」。
  def send_out!(on: nil)
    raise StandardError, '这张单已经退出去了' if sent_on.present?
    raise StandardError, '请先填退料明细' if items.empty?

    update!(sent_on: on.presence || Date.current, status: 'SENT')
    self
  end

  # 登记返回：按行填「这次回来多少」，累加到 returned_qty，再按齐不齐定单据状态。
  def receive_back!(rows, on: nil)
    raise StandardError, '这张单还没退出去' if sent_on.blank?

    transaction do
      apply_returned_rows(rows)
      reload
      update!(returned_on: on.presence || Date.current, status: derived_status)
    end
    self
  end

  private

  def apply_returned_rows(rows)
    Array(rows).each do |row|
      item = items.find_by(id: row[:id] || row['id'])
      next if item.nil?

      qty = (row[:returned_qty] || row['returned_qty']).to_d
      next if qty <= 0

      item.update!(returned_qty: item.returned_qty.to_d + qty)
    end
  end

  # 全部回来了＝已返回；回来一部分＝部分返回；一件没回＝维持已退出。
  def derived_status
    total = items.sum(&:qty).to_d
    back = items.sum(&:returned_qty).to_d
    return 'SENT' if back <= 0
    return 'RETURNED' if back >= total

    'PARTIAL'
  end

  def product_line_source = production_order

  def inherit_account_on_items
    items.each { |item| item.account_id ||= account_id }
  end
end
