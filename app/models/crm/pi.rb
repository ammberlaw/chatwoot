# 形式发票（Proforma Invoice）。业务在系统里建 PI、按模板改、导出 PDF 发客户。
# 买方/装运信息存快照（选客户带入、可改），改 PI 不影响客户档案。
# 状态：草稿(DRAFT) → 未付款(UNPAID) → 已付款(PAID) → 已作废(VOID)。付款后转生成销售订单（二期）。
#
# UNPAID 是单独一档：PI 已经发出去、但钱还没到。原来只有「草稿/已付款」两档，
# 业务员自己不掌握收款（迪拜这类单价金额都在财务对账），单子就只能一直挂「草稿」，
# 看不出「已发客户待收款」和「还没做完」的区别。
# == Schema Information
#
# Table name: crm_pis
#
#  id                   :bigint           not null, primary key
#  attention            :string
#  buyer_address        :text
#  buyer_company        :string
#  buyer_email          :string
#  buyer_eori           :string
#  buyer_tel            :string
#  company_header       :string
#  country_of_origin    :string
#  currency             :string           default("USD"), not null
#  issued_by            :string
#  pi_date              :datetime         not null
#  pi_no                :string           not null
#  port_of_destination  :string
#  port_of_shipment     :string
#  remark               :text
#  seller_email         :string
#  seller_mobile        :string
#  shipping_cost_label  :string
#  shipping_cost_micros :bigint
#  shipping_method      :string
#  status               :string           default("DRAFT"), not null
#  terms                :text
#  total_amount_micros  :bigint
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint
#  crm_customer_id      :bigint
#  crm_opportunity_id   :bigint
#  handled_by_id        :bigint
#  owner_id             :bigint
#
# Indexes
#
#  index_crm_pis_on_account_id             (account_id)
#  index_crm_pis_on_account_id_and_pi_no   (account_id,pi_no) UNIQUE
#  index_crm_pis_on_account_id_and_status  (account_id,status)
#  index_crm_pis_on_crm_customer_id        (crm_customer_id)
#  index_crm_pis_on_crm_opportunity_id     (crm_opportunity_id)
#  index_crm_pis_on_handled_by_id          (handled_by_id)
#  index_crm_pis_on_owner_id               (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (handled_by_id => users.id) ON DELETE => nullify
#
class Crm::Pi < ApplicationRecord
  STATUSES = %w[DRAFT UNPAID PAID VOID].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  # 经办人：实际建单的人（业绩仍归 owner=客户归属人，此字段仅留痕）。
  belongs_to :handled_by, class_name: 'User', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true

  has_many :pi_items, -> { order(:position, :id) },
           class_name: 'Crm::PiItem', foreign_key: :crm_pi_id,
           dependent: :destroy, inverse_of: :pi
  accepts_nested_attributes_for :pi_items, allow_destroy: true

  before_validation :generate_pi_no, on: :create
  before_save :compute_total

  validates :pi_no, presence: true,
                    uniqueness: { scope: :account_id, message: '号已存在，请换一个号（如加 -02 后缀），或直接打开原单编辑' }
  validates :pi_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  # 校验报错要直接给业务员看（前端弹的就是 full_messages），别露 Pi no / Pi date 这种列名。
  def self.human_attribute_name(attr, options = {})
    # full_message 拼的是「属性名 + 空格 + 消息」，故属性名只留「PI」，由消息自己接上「号…」。
    { 'pi_no' => 'PI', 'pi_date' => 'PI 日期', 'status' => '状态', 'currency' => '币种' }[attr.to_s] || super
  end

  private

  # PI 号：WT + YYYYMMDD（当天第二单起追加 -NN），可被显式传入覆盖。
  def generate_pi_no
    return if pi_no.present?

    base = "WT#{Time.zone.today.strftime('%Y%m%d')}"
    taken = account.crm_pis.where('pi_no = ? OR pi_no LIKE ?', base, "#{base}-%").pluck(:pi_no)
    self.pi_no = taken.include?(base) ? "#{base}-#{format('%02d', taken.size + 1)}" : base
  end

  # 总额 = 明细金额合计 + 运费（明细金额在 PiItem 保存前已各自算好）。
  def compute_total
    items_sum = pi_items.reject(&:marked_for_destruction?).sum { |i| i.amount_micros.to_i }
    self.total_amount_micros = items_sum + shipping_cost_micros.to_i
  end
end
