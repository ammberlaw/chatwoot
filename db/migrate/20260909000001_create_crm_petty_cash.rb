# 备用金台账：替代原来按部门/项目分 sheet 的 Excel（存入 / 支出 / 逐行结余 / 情况说明）。
# 一个部门或项目 = 一本台账（book），各自滚各自的结余；流水只增不改口径与 ERP 资金日记账一致，
# 将来 ERP 上线可整体吸收。
class CreateCrmPettyCash < ActiveRecord::Migration[7.1]
  def change
    create_books
    create_entries
    add_foreign_key :crm_petty_cash_entries, :crm_petty_cash_books, column: :crm_petty_cash_book_id, on_delete: :cascade
  end

  private

  def create_books
    create_table :crm_petty_cash_books do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      # 绑部门：用于「部门负责人看本部门」与审批联动落账；项目型台账（如 AI社媒GEO）可留空。
      t.bigint :org_department_id
      t.decimal :opening_balance, precision: 14, scale: 2, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.text :remark
      t.timestamps

      t.index [:account_id, :name], unique: true, name: 'index_crm_petty_cash_books_on_account_and_name'
      t.index [:account_id, :org_department_id], name: 'index_crm_petty_cash_books_on_account_and_dept'
    end
  end

  def create_entries
    create_table :crm_petty_cash_entries do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_petty_cash_book_id, null: false
      t.date :entry_date, null: false
      t.string :direction, null: false          # IN 存入 / OUT 支出
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.string :subject, null: false            # 事由（Excel 的「项目」列）
      t.string :channel                         # 资金渠道：现金/支付宝/微信/银行（原来混在事由文字里）
      t.string :category                        # 费用类别，选填，与「费用报销」审批的费用类型同一套
      t.bigint :handler_id                      # 经手人，选填
      t.text :remark                            # 情况说明
      t.bigint :oa_approval_request_id          # 来源审批单（备用金申请 / 费用报销自动落账）
      t.bigint :created_by_id
      t.timestamps

      t.index [:account_id, :crm_petty_cash_book_id, :entry_date],
              name: 'index_crm_petty_cash_entries_on_book_and_date'
      t.index :oa_approval_request_id, name: 'index_crm_petty_cash_entries_on_approval_request'
    end
  end
end
