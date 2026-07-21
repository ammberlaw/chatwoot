class Mes::StockEntryItem < ApplicationRecord
  ITEM_TYPES = %w[MATERIAL PRODUCT].freeze

  belongs_to :account
  belongs_to :stock_entry, class_name: 'Mes::StockEntry', inverse_of: :stock_entry_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true

  before_validation :inherit_account

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :qty, presence: true, numericality: { greater_than: 0 }

  # 实际过账数量：优先实收（来料核对），否则单据数量。
  def effective_qty
    (received_qty.presence || qty).to_d
  end

  private

  def inherit_account
    self.account_id ||= stock_entry&.account_id
  end
end
