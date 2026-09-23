# CRM 可配置选项项（客户分组 / 客户来源），支持二级层级 + 显示隐藏 + 排序。
# 客户表按 code 存储引用（存量枚举码保持不变，故不需迁移历史数据）。
# == Schema Information
#
# Table name: crm_option_items
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  category     :string           not null
#  code         :string           not null
#  name         :string           not null
#  position     :integer          default(0), not null
#  product_line :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  parent_id    :bigint
#
# Indexes
#
#  idx_crm_option_items_code  (account_id,category,code) UNIQUE
#  idx_crm_option_items_line  (account_id,category,product_line)
#  idx_crm_option_items_tree  (account_id,category,parent_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (parent_id => crm_option_items.id) ON DELETE => cascade
#
class Crm::OptionItem < ApplicationRecord
  # product_source_category：产品档案左侧「商品类别」树的**排序**。类别值本身来自
  # 产品的 source_category（金蝶那列），这里只存人工拖出来的顺序，不是分类字典。
  CATEGORIES = %w[customer_group customer_source product_group product_source_category].freeze
  # 限二级的类别（客户分组/来源）；product_group 为不限层级的产品分组树，只防环。
  TWO_LEVEL_CATEGORIES = %w[customer_group customer_source].freeze

  # 首次访问按现有枚举播种为一级项（含中文显示名）。
  DEFAULTS = {
    'customer_group' => [
      %w[KEY_ACCOUNT_WON 成交重点客户], %w[WON 成交客户], %w[SAMPLE_WON 成交样品客户],
      %w[NOT_WON 未成交客户], %w[SOCIAL_MEDIA 社媒开发客户]
    ],
    'customer_source' => [
      %w[ALIBABA 阿里巴巴国际站], %w[WEBSITE 官网], %w[EXHIBITION 展会],
      %w[REFERRAL 转介绍], %w[EMAIL 邮件开发], %w[OTHER 其他]
    ]
  }.freeze

  belongs_to :account
  belongs_to :parent, class_name: 'Crm::OptionItem', optional: true
  has_many :children, class_name: 'Crm::OptionItem', foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  before_validation :ensure_code

  validates :category, inclusion: { in: CATEGORIES }
  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: %i[account_id category] }
  validate :parent_same_account_and_category
  validate :single_level_depth
  validate :parent_not_descendant

  scope :for_category, ->(category) { where(category: category) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :id) }

  # 本节点 + 全部后代的 id（用于按分组筛选：点父节点连带其整棵子树的产品）。
  def self_and_descendant_ids
    ids = [id]
    frontier = [id]
    until frontier.empty?
      child_ids = self.class.where(account_id: account_id, parent_id: frontier).pluck(:id)
      child_ids -= ids
      ids.concat(child_ids)
      frontier = child_ids
    end
    ids
  end

  # 该账号该类别若为空，按现有枚举播种一级项。并发下靠唯一索引兜底。
  def self.ensure_defaults!(account, category)
    return if where(account_id: account.id, category: category).exists?

    DEFAULTS.fetch(category, []).each_with_index do |(code, name), index|
      create!(account: account, category: category, code: code, name: name, position: index)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  def ensure_code
    self.code ||= "OPT_#{SecureRandom.hex(4)}"
  end

  def parent_same_account_and_category
    return if parent_id.blank? || parent.blank?
    return if parent.account_id == account_id && parent.category == category

    errors.add(:parent_id, '父项须同账号同类别')
  end

  # 只允许二级（客户分组/来源）：子项的父项必须是一级。product_group 不限层级，跳过。
  def single_level_depth
    return if parent_id.blank? || parent.blank?
    return unless TWO_LEVEL_CATEGORIES.include?(category)

    errors.add(:parent_id, '只支持二级层级') if parent.parent_id.present?
  end

  # 不限层级类别防环：父项不能是自己或自己的后代。
  def parent_not_descendant
    return if parent_id.blank? || new_record?
    return unless parent_id == id || self_and_descendant_ids.include?(parent_id)

    errors.add(:parent_id, '不能选择自身或子孙作为上级')
  end
end
