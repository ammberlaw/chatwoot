class AddExtraExpensesToTiktokProfitRecords < ActiveRecord::Migration[7.1]
  def change
    # 其它费用清单：[{ "name" => "广告花费", "amount" => 1200.0 }, ...]，计入净利润。
    add_column :tiktok_profit_records, :extra_expenses, :jsonb, null: false, default: []
  end
end
