# 展会邀约记录：一场展会对一个客户的一次邀约，贯穿 待邀约→已邀约→已互动→已接受/谢绝。
# confirm_token 用于客户端免登录落地页（/crm_exhibition_invite/:token），客户在线确认到访回填 reply_*。
# == Schema Information
#
# Table name: crm_exhibition_invites
#
#  id                :bigint           not null, primary key
#  accepted_at       :datetime
#  confirm_token     :string           not null
#  declined_at       :datetime
#  interacted_at     :datetime
#  invited_at        :datetime
#  match_level       :string
#  reply_company     :string
#  reply_contact     :string
#  reply_name        :string
#  reply_note        :text
#  reply_products    :string
#  reply_visit_date  :date
#  stage             :string           default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_customer_id   :bigint           not null
#  crm_exhibition_id :bigint           not null
#  owner_id          :bigint
#
# Indexes
#
#  idx_crm_exhibition_invites_uniq                              (crm_exhibition_id,crm_customer_id) UNIQUE
#  index_crm_exhibition_invites_on_account_id                   (account_id)
#  index_crm_exhibition_invites_on_confirm_token                (confirm_token) UNIQUE
#  index_crm_exhibition_invites_on_crm_customer_id              (crm_customer_id)
#  index_crm_exhibition_invites_on_crm_exhibition_id            (crm_exhibition_id)
#  index_crm_exhibition_invites_on_crm_exhibition_id_and_stage  (crm_exhibition_id,stage)
#  index_crm_exhibition_invites_on_owner_id                     (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => cascade
#  fk_rails_...  (crm_exhibition_id => crm_exhibitions.id) ON DELETE => cascade
#
class Crm::ExhibitionInvite < ApplicationRecord
  belongs_to :account
  belongs_to :exhibition, class_name: 'Crm::Exhibition', foreign_key: :crm_exhibition_id
  belongs_to :customer, class_name: 'Crm::Customer', foreign_key: :crm_customer_id
  belongs_to :owner, class_name: 'User', optional: true

  # pending 待邀约 / invited 已邀约 / interacted 已互动 / accepted 已接受 / declined 谢绝
  STAGES = %w[pending invited interacted accepted declined].freeze

  validates :stage, inclusion: { in: STAGES }

  before_validation :ensure_token, on: :create

  scope :active_stage, -> { where.not(stage: 'declined') }

  # 标记到某阶段并记录对应时间戳（阶段只前进、时间戳只在首次置入时写）。
  def advance_to!(new_stage)
    return unless STAGES.include?(new_stage)

    ts = { 'invited' => :invited_at, 'interacted' => :interacted_at,
           'accepted' => :accepted_at, 'declined' => :declined_at }[new_stage]
    attrs = { stage: new_stage }
    attrs[ts] ||= Time.current if ts && self[ts].blank?
    update!(attrs)
  end

  # 客户免登录确认到访的落地页链接（邀请函里嵌入）。
  def public_confirm_url
    base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base}/crm_exhibition_invite/#{confirm_token}"
  end

  private

  def ensure_token
    self.confirm_token ||= SecureRandom.hex(16)
  end
end
