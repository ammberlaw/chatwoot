# == Schema Information
#
# Table name: mes_warehouses
#
#  id           :bigint           not null, primary key
#  code         :string           not null
#  is_active    :boolean          default(TRUE), not null
#  kind         :string
#  name         :string           not null
#  position     :integer
#  product_line :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  parent_id    :bigint
#
# Indexes
#
#  index_mes_warehouses_on_account_and_product_line  (account_id,product_line)
#  index_mes_warehouses_on_account_id                (account_id)
#  index_mes_warehouses_on_account_id_and_code       (account_id,code) UNIQUE
#  index_mes_warehouses_on_parent_id                 (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (parent_id => mes_warehouses.id) ON DELETE => nullify
#
class Mes::Warehouse < ApplicationRecord
  KINDS = %w[RAW WIP FINISHED SCRAP].freeze

  # 首访自动建的 4 个默认仓（code => [name, kind]）。
  DEFAULT_WAREHOUSES = {
    'RAW' => ['原料仓', 'RAW'],
    'WIP' => ['在制品仓', 'WIP'],
    'FINISHED' => ['成品仓', 'FINISHED'],
    'SCRAP' => ['废料仓', 'SCRAP']
  }.freeze

  belongs_to :account
  belongs_to :parent, class_name: 'Mes::Warehouse', optional: true
  has_many :children, class_name: 'Mes::Warehouse', foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent

  validates :code, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }, allow_blank: true

  scope :active, -> { where(is_active: true) }

  def self.ensure_defaults!(account)
    DEFAULT_WAREHOUSES.each_with_index do |(code, (name, kind)), index|
      account.mes_warehouses.find_or_create_by!(code: code) do |w|
        w.name = name
        w.kind = kind
        w.position = index
      end
    end
  end
end
