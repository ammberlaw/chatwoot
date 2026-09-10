# TK 板块两张台账：
# - 支出台账：店铺运营与部门日常开销（广告/物流/海外仓/达人合作/人员费用…），
#   与 CRM 备用金台账各记各的，TK 支出从备用金里独立出来。
# - 固定资产登记：拍摄设备/电脑/手机等，只登记不折旧（折旧留给 ERP 固定资产模块）。
class CreateTiktokExpensesAndAssets < ActiveRecord::Migration[7.1]
  def change
    create_expenses
    create_assets
  end

  private

  def create_expenses
    create_table :tiktok_expenses do |t|
      t.bigint :account_id, null: false
      # 部门必填、店铺选填：广告费挂到具体店铺，人员日结/办公这类只挂部门。
      t.bigint :department_id, null: false
      t.bigint :shop_id
      t.date :expense_date, null: false
      t.string :category, null: false
      t.string :subject, null: false
      t.decimal :amount, precision: 14, scale: 2, default: 0, null: false
      # 海外店铺常以 PHP/USD 付款，与利润表同款：存原币 + 落账时快照汇率与 RMB 金额。
      t.string :currency, default: 'CNY', null: false
      t.decimal :amount_cny, precision: 14, scale: 2, default: 0, null: false
      t.decimal :fx_rate, precision: 14, scale: 6, default: 0, null: false
      t.text :remark
      t.bigint :creator_id
      t.timestamps

      t.index [:account_id, :department_id, :expense_date], name: 'index_tiktok_expenses_on_dept_and_date'
      t.index [:account_id, :shop_id], name: 'index_tiktok_expenses_on_account_and_shop'
    end
  end

  def create_assets
    create_table :tiktok_assets do |t|
      t.bigint :account_id, null: false
      t.bigint :department_id, null: false
      t.string :name, null: false
      t.string :code
      t.string :category
      t.date :purchased_on
      t.decimal :amount, precision: 14, scale: 2, default: 0, null: false
      t.bigint :holder_id
      t.string :location
      t.string :status, default: 'IN_USE', null: false
      t.text :remark
      t.bigint :creator_id
      t.timestamps

      t.index [:account_id, :department_id], name: 'index_tiktok_assets_on_account_and_dept'
      t.index [:account_id, :code], name: 'index_tiktok_assets_on_account_and_code'
    end
  end
end
