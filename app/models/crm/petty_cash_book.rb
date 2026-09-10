# 备用金台账本：一个部门或项目一本，各自滚各自的结余（对应原 Excel 的一个 sheet）。
# == Schema Information
#
# Table name: crm_petty_cash_books
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  name              :string           not null
#  opening_balance   :decimal(14, 2)   default(0.0), not null
#  remark            :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  org_department_id :bigint
#
# Indexes
#
#  index_crm_petty_cash_books_on_account_and_dept  (account_id,org_department_id)
#  index_crm_petty_cash_books_on_account_and_name  (account_id,name) UNIQUE
#
class Crm::PettyCashBook < ApplicationRecord
  self.table_name = 'crm_petty_cash_books'

  belongs_to :account
  belongs_to :org_department, class_name: 'Org::Department', optional: true
  has_many :entries, class_name: 'Crm::PettyCashEntry', foreign_key: :crm_petty_cash_book_id,
                     inverse_of: :book, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }

  # 结余 = 期初 + 存入 − 支出。流水只增不改，任何时点都能跟现金/支付宝余额对上。
  def balance
    opening_balance.to_d + entries.where(direction: 'IN').sum(:amount) - entries.where(direction: 'OUT').sum(:amount)
  end
end
