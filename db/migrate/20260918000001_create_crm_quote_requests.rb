# 定制报价：业务员按产品线模板填参数提交，主管（或被转交的人）填价格回来。
#
# 与既有两个模块的分工：核价表是「已发布的标准价目」(只读查价)，报价单是「给客户的正式报价」
# (业务员自己填价)。这里补的是中间那一环——标准价目里没有的定制件，得先向上要个价。
class CreateCrmQuoteRequests < ActiveRecord::Migration[7.1]
  def change
    # 每条产品线一套参数模板（字段定义与 OA 审批模板同款 jsonb，前端渲染逻辑可复用）。
    create_table :crm_quote_request_templates do |t|
      t.references :account, null: false, index: true
      t.string :product_line, null: false
      t.string :name, null: false
      t.string :description
      t.jsonb :form_fields, null: false, default: []
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.bigint :creator_id
      t.timestamps
    end
    add_index :crm_quote_request_templates, [:account_id, :product_line, :active],
              name: 'idx_crm_qr_templates_line'

    create_table :crm_quote_requests do |t|
      t.references :account, null: false, index: true
      t.bigint :template_id, null: false
      t.bigint :applicant_id, null: false     # 提交的业务员
      t.bigint :pricer_id                     # 当前该谁报价（可转交）
      t.bigint :crm_customer_id               # 关联客户，选填
      t.string :request_no, null: false
      t.string :title, null: false
      t.string :product_line, null: false
      t.jsonb :form_data, null: false, default: {}
      t.string :status, null: false, default: 'PENDING'  # PENDING / QUOTED / CANCELLED
      t.integer :quantity

      # 报价结果
      t.bigint :quoted_price_micros
      t.string :quote_currency, default: 'USD'
      t.datetime :valid_until
      t.text :pricer_note
      t.datetime :quoted_at
      t.bigint :quoted_by_id

      t.timestamps
    end
    add_index :crm_quote_requests, [:account_id, :request_no], unique: true,
              name: 'idx_crm_quote_requests_no'
    add_index :crm_quote_requests, [:account_id, :status], name: 'idx_crm_quote_requests_status'
    add_index :crm_quote_requests, :applicant_id
    add_index :crm_quote_requests, :pricer_id

    # 转交记录：主管报不了价时手动推给别人（如总经理），要留痕谁转给谁、为什么。
    create_table :crm_quote_request_transfers do |t|
      t.references :account, null: false, index: true
      t.bigint :request_id, null: false
      t.bigint :from_user_id
      t.bigint :to_user_id, null: false
      t.text :reason
      t.timestamps
    end
    add_index :crm_quote_request_transfers, :request_id
  end
end
