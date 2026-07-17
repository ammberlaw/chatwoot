class AddCreatedByToCrmKpiSchemes < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_kpi_schemes, :created_by_id, :bigint
    add_index :crm_kpi_schemes, :created_by_id
    add_foreign_key :crm_kpi_schemes, :users, column: :created_by_id, on_delete: :nullify
  end
end
