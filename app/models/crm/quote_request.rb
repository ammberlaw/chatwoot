# 定制报价申请：业务员填参数 → 直属主管报价 → 回给业务员。
# 主管报不了的可以手动转给别人（如总经理），转交留痕见 Crm::QuoteRequestTransfer。
# == Schema Information
#
# Table name: crm_quote_requests
#
#  id                  :bigint           not null, primary key
#  form_data           :jsonb            not null
#  pricer_note         :text
#  product_line        :string           not null
#  quantity            :integer
#  quote_currency      :string           default("USD")
#  quoted_at           :datetime
#  quoted_price_micros :bigint
#  request_no          :string           not null
#  spec_template       :string
#  status              :string           default("PENDING"), not null
#  title               :string           not null
#  valid_until         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  applicant_id        :bigint           not null
#  crm_customer_id     :bigint
#  pricer_id           :bigint
#  quoted_by_id        :bigint
#  template_id         :bigint
#
# Indexes
#
#  idx_crm_quote_requests_no                 (account_id,request_no) UNIQUE
#  idx_crm_quote_requests_status             (account_id,status)
#  index_crm_quote_requests_on_account_id    (account_id)
#  index_crm_quote_requests_on_applicant_id  (applicant_id)
#  index_crm_quote_requests_on_pricer_id     (pricer_id)
#
class Crm::QuoteRequest < ApplicationRecord
  belongs_to :account
  # 平板电脑 / 商显工控用 MES 那份内置规格（前端 orderSpecFields.js，与生产订单同一份定义，
  # 那边加字段这边自动跟上），没有数据库模板；其它产品线才走自建模板。
  belongs_to :template, class_name: 'Crm::QuoteRequestTemplate', optional: true
  belongs_to :applicant, class_name: 'User'
  belongs_to :pricer, class_name: 'User', optional: true
  belongs_to :quoted_by, class_name: 'User', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  has_many :transfers, class_name: 'Crm::QuoteRequestTransfer', foreign_key: :request_id,
                       dependent: :destroy, inverse_of: :request
  has_many_attached :files

  audited

  STATUSES = %w[PENDING QUOTED CANCELLED].freeze

  before_validation :generate_request_no, on: :create

  validates :request_no, :title, :product_line, presence: true
  validates :request_no, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'PENDING') }
  scope :for_applicant, ->(user_id) { where(applicant_id: user_id) }
  scope :for_pricer, ->(user_id) { where(pricer_id: user_id) }

  def quoted_price
    quoted_price_micros && (quoted_price_micros / 1_000_000.0)
  end

  # 报价：记下价格、币种、有效期和说明，单子转为已报价。
  def quote!(user:, price_micros:, currency:, valid_until:, note:)
    update!(
      status: 'QUOTED', quoted_price_micros: price_micros, quote_currency: currency.presence || 'USD',
      valid_until: valid_until, pricer_note: note, quoted_at: Time.current, quoted_by_id: user.id
    )
  end

  # 转交给别人报价（主管报不了时）。当前报价人换人，留一条转交记录。
  def transfer!(from:, to:, reason:)
    transaction do
      transfers.create!(account_id: account_id, from_user_id: from&.id, to_user_id: to.id, reason: reason)
      update!(pricer_id: to.id)
    end
  end

  private

  # 单号 QR-YYYYMMDD-NN。与销售订单同款：算当天最大序号 +1，
  # 已删单不回填（这张表没有软删，但口径保持一致，避免将来加软删时重蹈覆辙）。
  def generate_request_no
    return if request_no.present?

    prefix = "QR-#{Time.zone.today.strftime('%Y%m%d')}"
    last = Crm::QuoteRequest.where(account_id: account_id)
                            .where('request_no LIKE ?', "#{prefix}-%")
                            .pick(Arel.sql("MAX(SPLIT_PART(request_no, '-', 3)::int)")) || 0
    self.request_no = format('%<p>s-%<n>02d', p: prefix, n: last + 1)
  end
end
