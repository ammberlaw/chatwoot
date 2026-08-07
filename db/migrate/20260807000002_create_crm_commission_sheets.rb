class CreateCrmCommissionSheets < ActiveRecord::Migration[7.1]
  def change
    # 财务身份：可查看全员「已通过」提成表并导出（与业务员身份叠加，罗家明本人也填表）。
    add_column :account_users, :crm_finance, :boolean, default: false, null: false

    # 提成表主单：一人一月一张，走 业务员填 → 主管审批 → 财务查看/导出。
    create_table :crm_commission_sheets do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id                       # 业务员（填报人）
      t.datetime :period_month, null: false    # 归属月（月初）
      t.string :status, null: false, default: 'DRAFT'  # DRAFT/SUBMITTED/APPROVED/RETURNED
      t.bigint :manager_id                     # 审批主管
      t.datetime :submitted_at
      t.datetime :approved_at
      t.datetime :returned_at
      t.bigint :returned_by_id
      t.text :return_reason
      t.text :remark
      t.timestamps
    end
    add_index :crm_commission_sheets, :account_id
    add_index :crm_commission_sheets, [:account_id, :period_month]
    add_index :crm_commission_sheets, [:account_id, :owner_id, :period_month],
              unique: true, name: 'uniq_commission_sheet_owner_month'
    add_index :crm_commission_sheets, :owner_id

    # 提成表明细行：一行一笔订单，按产品品类分组小计。金额一律整数微分存储。
    create_table :crm_commission_items do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_commission_sheet_id, null: false
      t.bigint :crm_sales_order_id             # 自动带出时关联来源订单
      t.integer :position, default: 0
      t.string :product_category               # 产品品类（平板/显示器…）用于分组
      t.string :country                        # 国家
      t.string :customer_name                  # 客户名称（快照）
      t.string :order_no                       # 订单编号 / PI 号
      t.bigint :order_amount_micros            # 订单金额
      t.string :currency, default: 'USD'       # 订单币种
      t.bigint :shipping_micros                # 运费金额
      t.bigint :received_amount_micros         # 收款金额（原币）
      t.decimal :exchange_rate, precision: 12, scale: 6  # 汇率
      t.bigint :received_rmb_micros            # 收款金额（RMB）
      t.bigint :sales_rmb_micros               # 销售金额（RMB）
      t.string :payment_channel                # 汇款途径
      t.datetime :payment_date                 # 到款日期
      t.string :product                        # 产品描述
      t.text :remark
      t.timestamps
    end
    add_index :crm_commission_items, :account_id
    add_index :crm_commission_items, :crm_commission_sheet_id
    add_index :crm_commission_items, :crm_sales_order_id
  end
end
