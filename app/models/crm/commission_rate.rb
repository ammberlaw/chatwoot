# 提成点配置：一账号一「产品品类 → 提成点」。rate 为百分数（3.0 = 3%）。
# 提成表按行的 product_category 匹配取点位，算提成工资时用（品类没配则点位为 0）。
class Crm::CommissionRate < ApplicationRecord
  belongs_to :account

  validates :product_category, presence: true,
            uniqueness: { scope: :account_id, message: '该品类已配置提成点' }
  validates :rate, numericality: { greater_than_or_equal_to: 0 }

  # { 品类 => 点位(百分数) } 便于逐行查表。
  def self.map_for(account)
    where(account_id: account.id).pluck(:product_category, :rate).to_h
  end
end
