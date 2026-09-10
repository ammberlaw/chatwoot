# 备用金流水：一行一笔，要么存入要么支出（原 Excel 里挤在同一行的存入+支出拆成两笔，
# 否则逐行结余算不出来）。附票据选传。
# == Schema Information
#
# Table name: crm_petty_cash_entries
#
#  id                     :bigint           not null, primary key
#  amount                 :decimal(14, 2)   not null
#  category               :string
#  channel                :string
#  direction              :string           not null
#  entry_date             :date             not null
#  remark                 :text
#  subject                :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  created_by_id          :bigint
#  crm_petty_cash_book_id :bigint           not null
#  handler_id             :bigint
#  oa_approval_request_id :bigint
#
# Indexes
#
#  index_crm_petty_cash_entries_on_approval_request  (oa_approval_request_id)
#  index_crm_petty_cash_entries_on_book_and_date     (account_id,crm_petty_cash_book_id,entry_date)
#
# Foreign Keys
#
#  fk_rails_...  (crm_petty_cash_book_id => crm_petty_cash_books.id) ON DELETE => cascade
#
class Crm::PettyCashEntry < ApplicationRecord
  self.table_name = 'crm_petty_cash_entries'

  DIRECTIONS = %w[IN OUT].freeze
  # 资金渠道：原来写在事由文字里（「备用金领用（支付宝）」），抽成字段后可按渠道汇总。
  CHANNELS = %w[现金 支付宝 微信 银行 其他].freeze
  # 费用类别与「费用报销」审批模板的费用类型同一套，选填。
  CATEGORIES = %w[差旅 招待 办公 交通 其他].freeze

  belongs_to :account
  belongs_to :book, class_name: 'Crm::PettyCashBook', foreign_key: :crm_petty_cash_book_id, inverse_of: :entries
  belongs_to :handler, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :approval_request, class_name: 'Oa::ApprovalRequest', foreign_key: :oa_approval_request_id,
                                inverse_of: false, optional: true

  has_many_attached :files

  validates :entry_date, :subject, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :amount, numericality: { greater_than: 0 }
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true

  scope :ordered, -> { order(:entry_date, :id) }
  scope :in_month, lambda { |month|
    date = Date.parse("#{month}-01")
    where(entry_date: date..date.end_of_month)
  }

  def signed_amount = direction == 'IN' ? amount.to_d : -amount.to_d
end
