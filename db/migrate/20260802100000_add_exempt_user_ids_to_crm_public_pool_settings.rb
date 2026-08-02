class AddExemptUserIdsToCrmPublicPoolSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_public_pool_settings, :exempt_user_ids, :bigint, array: true, default: [], null: false
  end
end
