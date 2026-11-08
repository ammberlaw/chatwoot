# 寄样记录：客户详情页右列那块占位（「即将上线：寄样状态、快递单号、客户反馈」）的真东西。
#
# 为什么不复用 mes_shipments：那是仓库出货单，要挂生产订单、挂仓库、走审批流。
# 业务员寄个样品给客户看不该走这一套——它是销售动作，不是生产动作。
#
# 刻意做得很轻：只记占位符承诺的三件事（寄了什么/到哪了/客户怎么说），
# 不做审批、不扣库存。真要扣库存的是批量出货，那条路已经有了。
class CreateCrmSamples < ActiveRecord::Migration[7.1]
  def change
    create_samples_table
    add_samples_indexes
  end

  private

  def create_samples_table
    create_table :crm_samples do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_customer_id, null: false
      # 寄样多半是为某个商机寄的；挂上之后商机能自动推到「样品中」那一阶段
      # （五个阶段里只有它一直没有对应单据，见 Crm::OpportunityStageSync）。
      t.bigint :crm_opportunity_id
      t.bigint :owner_id
      t.string :status, null: false, default: 'PENDING'
      # 寄了什么：[{ name, model, quantity }]。做成 jsonb 不另开明细表——
      # 一次寄样就那么两三样，为它建一张从表不划算（同 crm_sales_orders.line_items）。
      t.jsonb :items, null: false, default: []
      t.string :carrier
      t.string :tracking_no
      t.string :recipient
      t.datetime :sent_at
      t.datetime :delivered_at
      t.string :feedback_result
      t.text :feedback
      t.datetime :feedback_at
      t.text :remark
      t.timestamps
    end
  end

  def add_samples_indexes
    add_index :crm_samples, [:account_id, :crm_customer_id]
    add_index :crm_samples, [:account_id, :status]
    add_index :crm_samples, :crm_opportunity_id
    add_index :crm_samples, :owner_id
    # 按单号查件：客户问「我的样品到哪了」时直接搜。
    add_index :crm_samples, [:account_id, :tracking_no]
  end
end
