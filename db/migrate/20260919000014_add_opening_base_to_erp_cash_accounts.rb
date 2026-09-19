# 资金账户期初余额的**本位币**金额。
#
# 原来只有 opening_balance_micros（原币）。CNY 账户无所谓，外币账户就缺一块：
# 「20000 美元期初」在总账里折成多少人民币，表上无从得知——资金报表要出「折 CNY 合计」
# 时只能按 1:1 加（正是看板刚修掉的那个错），或者干脆不出这一列。
#
# 故意允许 NULL：外币账户的历史期初本位币是财务才知道的数，回填不了。
# 报表遇到 NULL 会把该账户的本位币列显示为「—」并在合计处提示，不猜、也不静默算错。
class AddOpeningBaseToErpCashAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :erp_cash_accounts, :opening_base_amount_micros, :bigint, null: true

    # 本位币账户的期初本位币就是它自己，直接回填；外币留空等财务补。
    execute <<~SQL.squish
      UPDATE erp_cash_accounts
         SET opening_base_amount_micros = opening_balance_micros
       WHERE currency = 'CNY'
    SQL
  end

  def down
    remove_column :erp_cash_accounts, :opening_base_amount_micros
  end
end
