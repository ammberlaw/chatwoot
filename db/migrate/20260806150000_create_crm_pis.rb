class CreateCrmPis < ActiveRecord::Migration[7.1]
  def change
    # 形式发票（Proforma Invoice）：业务在系统里建 PI、按模板改、导出 PDF 发客户；
    # 付款后（二期）转生成销售订单。买方/装运信息存快照，改 PI 不影响客户档案。
    create_table :crm_pis do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.bigint :owner_id
      t.bigint :crm_customer_id
      t.bigint :contact_id

      t.string :pi_no, null: false          # INVOICE NO.（WT+日期）
      t.datetime :pi_date, null: false      # DATE
      t.string :status, null: false, default: 'DRAFT' # DRAFT / PAID / VOID
      t.string :currency, null: false, default: 'USD'

      # BILL TO（买方快照，选客户自动带入、可改）
      t.string :attention
      t.string :buyer_company
      t.text :buyer_address
      t.string :buyer_email
      t.string :buyer_tel
      t.string :buyer_eori

      # SHIPMENT & PAYMENT
      t.string :port_of_shipment
      t.string :port_of_destination
      t.string :country_of_origin
      t.string :shipping_method

      # 运费 + 总额
      t.string :shipping_cost_label
      t.bigint :shipping_cost_micros
      t.bigint :total_amount_micros

      t.text :terms          # TERMS & CONDITIONS
      t.string :issued_by    # ISSUED BY（默认业务员名，可改）
      t.text :remark

      t.timestamps
    end

    add_index :crm_pis, [:account_id, :pi_no], unique: true
    add_index :crm_pis, [:account_id, :status]
    add_index :crm_pis, :crm_customer_id
    add_index :crm_pis, :owner_id

    create_table :crm_pi_items do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :crm_pi, null: false, foreign_key: true, index: true
      t.integer :position, null: false, default: 0
      t.string :model            # MODEL
      t.text :description        # DESCRIPTION
      t.decimal :quantity, precision: 12, scale: 2
      t.bigint :unit_price_micros
      t.bigint :amount_micros
      t.timestamps
      # PICTURE 走 ActiveStorage has_one_attached :picture，无需列
    end
  end
end
