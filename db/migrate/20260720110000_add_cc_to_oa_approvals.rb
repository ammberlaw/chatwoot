class AddCcToOaApprovals < ActiveRecord::Migration[7.1]
  def change
    add_column :oa_approval_templates, :cc_user_ids, :bigint, array: true, default: [], null: false
    add_column :oa_approval_requests, :cc_user_ids, :bigint, array: true, default: [], null: false
    add_index :oa_approval_requests, :cc_user_ids, using: :gin
  end
end
