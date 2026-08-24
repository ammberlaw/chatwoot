class AddDeactivatedAtToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :deactivated_at, :datetime
  end
end
