class CreateErpSettings < ActiveRecord::Migration[7.1]
  def change
    # 账套级财务政策，一账户一行。目前只放坏账计提比例（按账龄段），
    # 后续账套级政策（如整数差异容差）也落这里，不再为每个开关单开一张表。
    create_table :erp_settings do |t|
      t.references :account, null: false, index: { unique: true }
      t.jsonb :bad_debt_rates, null: false, default: {}
      t.timestamps
    end
  end
end
