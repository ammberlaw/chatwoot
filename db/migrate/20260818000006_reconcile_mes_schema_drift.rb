# MES schema 漂移修复：本地(chatwoot_dev)通过 schema:load 直接有这些表/列，但生产是逐条 migrate
# 上来的，缺 6 张表 + account_users.mes_roles(多值角色数组) 列/索引，且这些缺失项没有对应迁移文件。
# 本迁移带存在性判断，可安全在两边运行：本地已存在则跳过，生产不存在则创建。补齐后 MES 才能在生产正常鉴权。
class ReconcileMesSchemaDrift < ActiveRecord::Migration[7.1]
  def up
    unless table_exists?(:mes_board_owners)
      create_table :mes_board_owners do |t|
        t.bigint :account_id, null: false
        t.string :board_key, null: false
        t.bigint :manager_ids, default: [], null: false, array: true
        t.timestamps
        t.index [:account_id, :board_key], unique: true, name: 'index_mes_board_owners_on_account_id_and_board_key'
        t.index :account_id, name: 'index_mes_board_owners_on_account_id'
      end
    end

    unless table_exists?(:mes_bom_templates)
      create_table :mes_bom_templates do |t|
        t.bigint :account_id, null: false
        t.string :name, null: false
        t.string :product_line
        t.decimal :base_qty, precision: 14, scale: 3, default: '1.0', null: false
        t.string :unit
        t.integer :purchasing_days
        t.integer :material_inbound_days
        t.integer :picking_days
        t.integer :production_days
        t.integer :fg_inbound_days
        t.bigint :owner_id
        t.text :remark
        t.timestamps
        t.index :account_id, name: 'index_mes_bom_templates_on_account_id'
        t.index :owner_id, name: 'index_mes_bom_templates_on_owner_id'
        t.index :product_line, name: 'index_mes_bom_templates_on_product_line'
      end
    end

    unless table_exists?(:mes_bom_template_items)
      create_table :mes_bom_template_items do |t|
        t.bigint :account_id, null: false
        t.bigint :bom_template_id, null: false
        t.string :material_no
        t.string :material_name
        t.string :specification
        t.string :unit
        t.decimal :qty, precision: 14, scale: 3, null: false
        t.text :remark
        t.timestamps
        t.index :account_id, name: 'index_mes_bom_template_items_on_account_id'
        t.index :bom_template_id, name: 'index_mes_bom_template_items_on_bom_template_id'
      end
    end

    unless table_exists?(:mes_document_returns)
      create_table :mes_document_returns do |t|
        t.bigint :account_id, null: false
        t.string :returnable_type, null: false
        t.bigint :returnable_id, null: false
        t.bigint :returned_by_id
        t.text :reason, null: false
        t.string :from_board_key
        t.string :to_board_key, null: false
        t.datetime :resolved_at
        t.bigint :resolved_by_id
        t.timestamps
        t.index :account_id, name: 'index_mes_document_returns_on_account_id'
        t.index [:returnable_type, :returnable_id, :resolved_at], name: 'index_mes_document_returns_on_returnable_and_resolved'
        t.index [:returnable_type, :returnable_id], name: 'index_mes_document_returns_on_returnable'
      end
    end

    unless table_exists?(:mes_notifications)
      create_table :mes_notifications do |t|
        t.bigint :account_id, null: false
        t.bigint :recipient_id, null: false
        t.bigint :production_order_id
        t.string :kind, null: false
        t.string :title, null: false
        t.text :body
        t.datetime :read_at
        t.timestamps
        t.index [:account_id, :recipient_id, :read_at], name: 'idx_on_account_id_recipient_id_read_at_4123636370'
        t.index :account_id, name: 'index_mes_notifications_on_account_id'
        t.index :production_order_id, name: 'index_mes_notifications_on_production_order_id'
      end
    end

    unless table_exists?(:mes_supplier_items)
      create_table :mes_supplier_items do |t|
        t.bigint :account_id, null: false
        t.bigint :supplier_id, null: false
        t.bigint :mes_material_id
        t.string :material_code, null: false
        t.string :name, null: false
        t.string :color, null: false
        t.string :specification, null: false
        t.string :unit, null: false
        t.decimal :unit_price, precision: 14, scale: 4, null: false
        t.string :category
        t.timestamps
        t.index :account_id, name: 'index_mes_supplier_items_on_account_id'
        t.index :category, name: 'index_mes_supplier_items_on_category'
        t.index :mes_material_id, name: 'index_mes_supplier_items_on_mes_material_id'
        t.index [:supplier_id, :material_code], unique: true, name: 'index_mes_supplier_items_on_supplier_id_and_material_code'
        t.index :supplier_id, name: 'index_mes_supplier_items_on_supplier_id'
      end
    end

    # 多值 MES 角色数组（生产仅有旧的单值 mes_role）——补齐后 effective_mes_roles 才不报错。
    unless column_exists?(:account_users, :mes_roles)
      add_column :account_users, :mes_roles, :string, array: true, default: [], null: false
    end
    unless index_exists?(:account_users, :mes_roles, name: 'index_account_users_on_mes_roles')
      add_index :account_users, :mes_roles, using: :gin, name: 'index_account_users_on_mes_roles'
    end

    add_fk_safe(:mes_board_owners, :accounts)
    add_fk_safe(:mes_bom_templates, :users, column: :owner_id, on_delete: :nullify)
    add_fk_safe(:mes_bom_template_items, :mes_bom_templates, column: :bom_template_id, on_delete: :cascade)
    add_fk_safe(:mes_document_returns, :accounts)
    add_fk_safe(:mes_notifications, :mes_production_orders, column: :production_order_id, on_delete: :cascade)
    add_fk_safe(:mes_notifications, :users, column: :recipient_id, on_delete: :cascade)
    add_fk_safe(:mes_supplier_items, :mes_materials, on_delete: :nullify)
    add_fk_safe(:mes_supplier_items, :mes_suppliers, column: :supplier_id, on_delete: :cascade)
  end

  # 漂移修复不做回滚（回滚会误删生产 MES 数据）；如需撤销请单独手工处理。
  def down; end

  private

  def add_fk_safe(from, to, **options)
    exists = options[:column] ? foreign_key_exists?(from, to, column: options[:column]) : foreign_key_exists?(from, to)
    return if exists

    add_foreign_key(from, to, **options)
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::DuplicateObject)
  end
end
