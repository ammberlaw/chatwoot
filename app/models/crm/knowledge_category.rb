# 知识库文档分类（账号级、用户可管理）。看板列与文档分类下拉均取自此表。
# == Schema Information
#
# Table name: crm_knowledge_categories
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_crm_knowledge_categories_on_account_id           (account_id)
#  index_crm_knowledge_categories_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::KnowledgeCategory < ApplicationRecord
  DEFAULT_NAMES = %w[产品目录 FAQ 售后政策 报价模板 公司资质 操作手册 产品规格书 收款账户].freeze

  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :ordered, -> { order(:position, :id) }

  # 账号首次访问时补齐默认分类（幂等：已有分类则跳过）。
  def self.seed_defaults!(account)
    return if account.crm_knowledge_categories.exists?

    DEFAULT_NAMES.each_with_index do |name, index|
      account.crm_knowledge_categories.create!(name: name, position: index)
    end
  end
end
