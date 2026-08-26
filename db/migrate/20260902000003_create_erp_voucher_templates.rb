class CreateErpVoucherTemplates < ActiveRecord::Migration[7.1]
  def change
    # 凭证模板：每月重复的分录（计提工资、房租、折旧…）存一份，新建凭证时一键带出。
    # 分录直接存 jsonb——模板是「录入草稿」，不参与记账，没必要再开一张分录表。
    create_table :erp_voucher_templates do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :summary
      t.jsonb :lines, null: false, default: []
      t.bigint :created_by_id
      t.timestamps

      t.index %i[account_id name], unique: true
    end
  end
end
