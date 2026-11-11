# 一次主动拓客任务：目标市场 + AI 生成的理想客户画像和本地化关键词。
# == Schema Information
#
# Table name: crm_lead_campaigns
#
#  id                     :bigint           not null, primary key
#  auto_run               :boolean          default(FALSE), not null
#  auto_run_at            :datetime
#  dead_keywords          :jsonb
#  default_customer_group :string
#  evidence               :jsonb            not null
#  keywords               :jsonb            not null
#  last_error             :text
#  name                   :string           not null
#  product_hint           :string
#  profile                :jsonb            not null
#  profiled_at            :datetime
#  run_model              :string
#  screen_criteria        :text
#  search_cursor          :jsonb            not null
#  searched_at            :datetime
#  seed_keywords          :string
#  shared                 :boolean          default(TRUE), not null
#  status                 :string           default("DRAFT"), not null
#  target_count           :integer          default(60), not null
#  target_markets         :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  created_by_id          :bigint
#  owner_id               :bigint
#
# Indexes
#
#  index_crm_lead_campaigns_on_account_id_and_status  (account_id,status)
#  index_crm_lead_campaigns_on_created_by_id          (created_by_id)
#  index_crm_lead_campaigns_on_owner_id               (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Crm::LeadCampaign < ApplicationRecord
  self.table_name = 'crm_lead_campaigns'

  # DRAFT 刚建/画像没跑出来 → PROFILED 画像好了，可以去搜 → SEARCHING 搜索中
  # → DONE 搜完了。失败停在原状态并写 last_error，人能重跑。
  STATUSES = %w[DRAFT PROFILED SEARCHING DONE].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  attr_readonly :created_by_id
  has_many :leads, class_name: 'Crm::Lead', foreign_key: :crm_lead_campaign_id,
                   dependent: :destroy, inverse_of: :campaign

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  # 画像里哪几条是模型推的（没有成交数据撑着）。发开发信之前这几条要人核实。
  def inferred_fields = Array(evidence['inferred'])

  def keywords_for(market)
    Array(keywords).select { |k| k['market'].to_s.casecmp?(market.to_s) }
  end
end
