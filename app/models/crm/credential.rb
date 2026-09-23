# 一条账号记录。password 加密入库（复用 mail_account 那套 ACTIVE_RECORD_ENCRYPTION_* 密钥）。
#
# 两档归属（同知识库的公司文档/我的文档）：
#   owner_id 为空 = 公司条目，挂分组、按分组名单授权、每次查看留痕
#   owner_id 有值 = 个人条目，创建人独占（管理员也看不到）、不分组、不留痕
#
# 刻意不加 audited：审计表会把改动前后的值原样留下，密码留痕等于多存一份明文。
# == Schema Information
#
# Table name: crm_credentials
#
#  id                      :bigint           not null, primary key
#  name                    :string           not null
#  note                    :text
#  password                :text
#  position                :integer          default(0), not null
#  url                     :string
#  username                :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  creator_id              :bigint
#  crm_credential_group_id :bigint
#  owner_id                :bigint
#  updated_by_id           :bigint
#
# Indexes
#
#  idx_crm_credentials_group_pos        (crm_credential_group_id,position)
#  idx_crm_credentials_owner            (account_id,owner_id)
#  index_crm_credentials_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_credential_group_id => crm_credential_groups.id) ON DELETE => cascade
#
class Crm::Credential < ApplicationRecord
  self.table_name = 'crm_credentials'

  encrypts :password

  belongs_to :account
  # 个人条目不挂分组，故 optional
  belongs_to :group, class_name: 'Crm::CredentialGroup', foreign_key: :crm_credential_group_id,
                     inverse_of: :credentials, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :creator, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  has_many :views, class_name: 'Crm::CredentialView', foreign_key: :crm_credential_id,
                   inverse_of: :credential, dependent: :delete_all

  validates :name, presence: true
  validate :group_or_owner

  scope :ordered, -> { order(:position, :id) }
  scope :company, -> { where(owner_id: nil) }
  scope :personal_of, ->(user_id) { where(owner_id: user_id) }

  def personal? = owner_id.present?

  def password?
    password.present?
  end

  private

  # 二选一：要么是挂在分组下的公司条目，要么是有归属人的个人条目。
  # 两者都空的记录谁都看不见（等于凭空消失），两者都有则授权口径自相矛盾。
  def group_or_owner
    return if crm_credential_group_id.present? ^ owner_id.present?

    errors.add(:base, '公司条目须选分组，个人条目不挂分组')
  end
end
