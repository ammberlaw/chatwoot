# 一条拓客线索：一家潜在客户公司 + 一个联系人。
#
# 邮箱默认是**锁着的**（Apollo 的搜索只告诉你 has_email，解锁要单独花 credits）。
# 做成人工点一下才解锁，而不是搜到就全解——一次任务几百条，全解既烧额度，
# 也没人看得过来。
# == Schema Information
#
# Table name: crm_leads
#
#  id                   :bigint           not null, primary key
#  city                 :string
#  claimed_at           :datetime
#  company_name         :string
#  country              :string
#  discarded_at         :datetime
#  domain               :string
#  email                :string
#  email_status         :string
#  industry             :string
#  linkedin_url         :string
#  person_name          :string
#  raw                  :jsonb            not null
#  status               :string           default("FOUND"), not null
#  title                :string
#  unlocked_at          :datetime
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  apollo_person_id     :string
#  crm_customer_id      :bigint
#  crm_lead_campaign_id :bigint           not null
#  discarded_by_id      :bigint
#  dup_customer_id      :bigint
#  owner_id             :bigint
#  unlocked_by_id       :bigint
#
# Indexes
#
#  index_crm_leads_on_account_and_campaign            (account_id,crm_lead_campaign_id)
#  index_crm_leads_on_account_id_and_domain           (account_id,domain)
#  index_crm_leads_on_account_id_and_owner_id         (account_id,owner_id)
#  index_crm_leads_on_account_id_and_status           (account_id,status)
#  index_crm_leads_on_apollo_person_id                (apollo_person_id)
#  index_crm_leads_on_unlocked_by_id_and_unlocked_at  (unlocked_by_id,unlocked_at)
#
class Crm::Lead < ApplicationRecord
  self.table_name = 'crm_leads'

  # FOUND 搜到了（邮箱还锁着） → UNLOCKED 解锁了联系方式
  # → CLAIMED 已建档进 CRM ／ DISCARDED 看过了不要
  # RELEASED 保护期内没动静、被别人重新挖走了（见下面的保护期）
  STATUSES = %w[FOUND UNLOCKED CLAIMED DISCARDED RELEASED].freeze

  # 线索保护期：**领了**才归你，这些天里别人看不见也领不走。
  #
  # 为什么要有期限：十个业务员用同一个池子，不给独占会全员撞在同一批公司上
  # （实测两个同词任务 153 家重合 152 家）；但只给独占不给期限，
  # 客户就烂在一个人手里——领了不跟进，别人还看不见。
  #
  # 比客户公海（30 天）短一半：线索还没建立任何关系，压一个月纯属浪费。
  HOLD_DAYS = 14

  # 一个人手上最多压多少条没处理完的。防「先领为敬」把池子扫空。
  HOLD_LIMIT = 60

  belongs_to :account
  belongs_to :campaign, class_name: 'Crm::LeadCampaign', foreign_key: :crm_lead_campaign_id,
                        inverse_of: :leads
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :unclaimed, -> { where(status: %w[FOUND UNLOCKED]) }

  # 还在某人手上的（保护期内）。
  # 建了档的永远算（已经是他的客户，归属走客户那套公海规则）；
  # 领了之后 HOLD_DAYS 天内算他的，过期自动回池。
  scope :holding, lambda {
    where(status: 'CLAIMED')
      .or(where(status: %w[FOUND UNLOCKED]).where.not(owner_id: nil)
            .where(claimed_at: HOLD_DAYS.days.ago..))
  }

  # 还在池子里、谁都能领的：没人领过，或者领了但保护期已过。
  # **不共享的任务不进池**——那是负责人自己的私活，别人看不见也领不走。
  scope :in_pool, lambda {
    free = where(status: %w[FOUND UNLOCKED])
           .where(owner_id: nil).or(
             where(status: %w[FOUND UNLOCKED]).where(claimed_at: ...HOLD_DAYS.days.ago)
           )
    free.where(crm_lead_campaign_id: Crm::LeadCampaign.where(shared: true).select(:id))
  }

  # 这条线索现在属于谁（保护期过了就不属于任何人）。
  def holder_id
    return owner_id if status == 'CLAIMED'
    return nil if owner_id.blank? || claimed_at.blank? || claimed_at < HOLD_DAYS.days.ago

    owner_id
  end

  # Apollo 搜索阶段只给 has_email 布尔值；解锁后才有真地址。
  def email_available? = raw['has_email'].present? || email.present?

  # 这家公司是不是我们已经在跟的（按域名比，口径同建档查重）。
  # 搜出来一堆早就是自家客户的公司，是这类工具最常见的浪费。
  def duplicate_of_existing? = dup_customer_id.present?
end
