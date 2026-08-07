class AddCrmPiSellerProfile < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_pi_seller_profiles do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id
      t.string :contact_name
      t.string :mobile
      t.string :email

      t.timestamps
    end
    add_index :crm_pi_seller_profiles, [:account_id, :owner_id],
              unique: true, name: 'idx_crm_pi_seller_profiles_account_owner'

    # PI 上的卖方联系方式快照（建单时从业务员预录带入、可当次改）。
    # 联系人姓名复用已有的 issued_by 列（Contact 行与 ISSUED BY 行同名）。
    add_column :crm_pis, :seller_mobile, :string
    add_column :crm_pis, :seller_email, :string
  end
end
