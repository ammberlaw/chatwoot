# 收信黑名单的一条规则。
#
# 为什么要有：「标记垃圾邮件」只改那一封的 folder，不留任何记忆——
# 同一家推销公司下周再发，照样进收件箱（实查 mail.theroyalalbatross.asia
# 标了 8 封、收件箱里还躺着 3 封）。
#
# 拦截动作是**在入库前直接丢弃**（和已有的 notification_sender? 一个路子），
# 不是收进来再挪文件夹：收进来就还会占列表、进搜索、喂给 AI 摘要。
# 代价是丢了就找不回来，所以规则上有两条硬护栏（见 BLOCKED_* ），
# 并且每条规则记拦截数和最近一封，误伤看得见、随时能删。
# == Schema Information
#
# Table name: crm_mail_blocklists
#
#  id                   :bigint           not null, primary key
#  blocked_count        :integer          default(0), not null
#  last_blocked_at      :datetime
#  last_blocked_from    :string
#  last_blocked_subject :string
#  note                 :string
#  value                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  created_by_id        :bigint
#
# Indexes
#
#  index_crm_mail_blocklists_on_account_id_and_value  (account_id,value) UNIQUE
#
class Crm::MailBlocklist < ApplicationRecord
  self.table_name = 'crm_mail_blocklists'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  validates :value, presence: true, uniqueness: { scope: :account_id }

  before_validation :normalize_value

  # 公共邮箱域名一律不许拉黑：一条 gmail.com 规则就能把 292 封客户来信全掐掉。
  # （生产上真有人手滑把一封 gmail 标成了垃圾邮件。）
  FREE_MAIL_DOMAINS = %w[
    gmail.com googlemail.com outlook.com hotmail.com live.com msn.com
    yahoo.com yahoo.co.jp ymail.com aol.com icloud.com me.com mac.com
    qq.com 163.com 126.com yeah.net sina.com sina.cn sohu.com foxmail.com
    naver.com daum.net hanmail.net web.de gmx.de gmx.com mail.ru yandex.ru
    protonmail.com proton.me zoho.com
  ].freeze

  # 自己公司的收信域名也不许拉黑，否则内部邮件全进不来。
  def self.own_domains(account)
    account.crm_mail_accounts.pluck(:email_address)
           .filter_map { |a| a.to_s.split('@').last.presence&.downcase }.uniq
  end

  def self.rejection_reason(account, value)
    value = value.to_s.strip.downcase
    return '请填写域名或完整邮箱地址' if value.blank?
    return '格式不对：域名形如 example.com，地址形如 a@example.com' unless value.match?(/\A(@?[a-z0-9.-]+\.[a-z]{2,}|[^@\s]+@[a-z0-9.-]+\.[a-z]{2,})\z/i)

    domain = value.include?('@') ? value.split('@').last : value.delete_prefix('@')
    return "#{domain} 是公共邮箱域名，拉黑会连客户来信一起掐掉" if FREE_MAIL_DOMAINS.include?(domain)
    return "#{domain} 是本公司收信域名，拉黑会收不到内部邮件" if own_domains(account).include?(domain)

    nil
  end

  # from 可能是「张三 <a@b.com>」，取尖括号里的那段。
  def self.sender_address(from)
    raw = from.to_s
    (raw[/<([^>]+)>/, 1] || raw).strip.downcase
  end

  # 命中这个发件人吗。域名规则连子域名一起拦：
  # 拉黑 theroyalalbatross.asia 要能挡住 mail.theroyalalbatross.asia。
  def matches?(address)
    return false if address.blank?

    return address == value if value.include?('@')

    domain = address.split('@').last.to_s
    domain == value || domain.end_with?(".#{value}")
  end

  def record_hit!(from, subject)
    update_columns(blocked_count: blocked_count + 1, last_blocked_at: Time.current, # rubocop:disable Rails/SkipsModelValidations
                   last_blocked_from: from.to_s[0, 255], last_blocked_subject: subject.to_s[0, 255],
                   updated_at: Time.current)
  end

  private

  def normalize_value
    self.value = value.to_s.strip.downcase.delete_prefix('@')
  end
end
