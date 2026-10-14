# == Schema Information
#
# Table name: mes_bom_items
#
#  id                           :bigint           not null, primary key
#  amount_micros                :bigint
#  aux_attribute_name           :string
#  blocked_at                   :datetime
#  blocker_cleared_at           :datetime
#  blocker_kind                 :string
#  blocker_note                 :text
#  category                     :string           default("MACHINE"), not null
#  material_name                :string
#  material_no                  :string
#  production_note              :text
#  purchase_note                :text
#  qty                          :decimal(14, 3)   not null
#  rate_micros                  :bigint
#  remark                       :text
#  specification                :string
#  suggested_purchase_qty       :decimal(14, 3)
#  unit                         :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  blocker_owner_id             :bigint
#  bom_id                       :bigint           not null
#  crm_product_aux_attribute_id :bigint
#  mes_material_id              :bigint
#
# Indexes
#
#  idx_mes_bom_items_on_aux_attr           (crm_product_aux_attribute_id)
#  index_mes_bom_items_on_account_id       (account_id)
#  index_mes_bom_items_on_bom_and_blocker  (bom_id,blocker_kind)
#  index_mes_bom_items_on_bom_id           (bom_id)
#  index_mes_bom_items_on_mes_material_id  (mes_material_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_id => mes_boms.id) ON DELETE => cascade
#  fk_rails_...  (crm_product_aux_attribute_id => crm_product_aux_attributes.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#
class Mes::BomItem < ApplicationRecord
  # 这颗料卡在哪。刻意按「等谁」分类而不是按「什么问题」——看的人第一反应是去找人。
  BLOCKER_LABELS = {
    'WAITING_CUSTOMER' => '等客户确认',
    'WAITING_FILE' => '等业务文件',
    'WAITING_ENGINEERING' => '等工程确认',
    'SAMPLING' => '打样中',
    'OTHER' => '其它'
  }.freeze
  BLOCKER_KINDS = BLOCKER_LABELS.keys.freeze

  # 用料分类：整机生产物料（决定能否开产）/ 包装物料（打包用，未到不挡生产）。
  CATEGORIES = %w[MACHINE PACKAGING].freeze

  belongs_to :account
  belongs_to :bom, class_name: 'Mes::Bom', inverse_of: :bom_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  # 本行选中的辅助属性（同一物料编码下的变体，单选）。
  belongs_to :crm_product_aux_attribute, class_name: 'Crm::ProductAuxAttribute', optional: true
  # 卡点等谁解决（通常是业务或工程，不是采购）
  belongs_to :blocker_owner, class_name: 'User', optional: true

  before_validation :inherit_account
  before_validation :nilify_blank_blocker
  before_save :snapshot_aux_attribute_name
  before_save :stamp_blocker_times

  # 照纸质生产任务单直接填：物料名称/用量必填，规格/编码/单位/备注选填。
  validates :material_name, presence: true
  validates :qty, presence: true, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :blocker_kind, inclusion: { in: BLOCKER_KINDS }, allow_blank: true

  scope :blocked, -> { where.not(blocker_kind: nil).where(blocker_cleared_at: nil) }

  # 卡点：这颗料为什么还没下采购单。原来系统只认「下了单 / 没下单」，没下单的一律
  # 看着像采购在拖，实际上一大半是在等客户确认、等业务发文件、等打样——责任人不在采购。
  # 用户原话：「其余相关的人怎么看到这个单问题点是卡在哪里呢？」
  def blocked? = blocker_kind.present? && blocker_cleared_at.nil?

  def blocker_label = BLOCKER_LABELS[blocker_kind]

  # 卡了多少天——交期谈判时要的就是这个数。
  def blocked_days
    return nil unless blocked? && blocked_at.present?

    ((Time.current - blocked_at) / 1.day).floor
  end

  private

  # 卡点的起止时间自己维护，前端只管传「卡在哪」：
  # 新卡上 → 记起始时间（「卡了几天」要靠它）；解除 → 记清除时间，留痕不删。
  def stamp_blocker_times
    return unless blocker_kind_changed?

    if blocker_kind.present?
      # 解除过又卡住：天数从这次重新开始算，不是从第一次卡住那天。
      self.blocked_at = Time.current if blocked_at.blank? || blocker_cleared_at.present?
      self.blocker_cleared_at = nil
    elsif blocked_at.present?
      self.blocker_cleared_at = Time.current
    end
  end

  # 表单清空卡点下拉送来的是空串，不是 nil；留着空串会被 `blocked` 口径当成「还卡着」，
  # 列表上冒出一个没有名字的标签。
  def nilify_blank_blocker
    self.blocker_kind = nil if blocker_kind.blank?
  end

  # 嵌套创建时从父 BOM 继承租户。
  def inherit_account
    self.account_id ||= bom&.account_id
  end

  # 存一份属性名：属性以后改名或停用，已下发的 BOM 还得显示当时选的是什么。
  def snapshot_aux_attribute_name
    return unless crm_product_aux_attribute_id_changed?

    self.aux_attribute_name = crm_product_aux_attribute&.name
  end
end
