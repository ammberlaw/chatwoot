class AddSalesRankToAccountUsers < ActiveRecord::Migration[7.1]
  def up
    # 「计入业绩排行」由人工勾选，不靠系统猜。
    # 原先想按规则自动判（业务员 + 有客户 + 非生产岗），但规则再细也会有例外：
    # 副管理员兼着跑业务要算、挂 manager 的生产主管不算、建了没用的空号不算。
    # 与其堆条件，不如给个开关让人事自己点。
    add_column :account_users, :in_sales_rank, :boolean, null: false, default: false

    # 初始值＝现在实际在跑业务的人：业务员/主管身份、在职、手上有客户。
    # 这样上线即可用，不用再手工勾一遍。
    execute <<~SQL
      UPDATE account_users au SET in_sales_rank = true
      WHERE au.deactivated_at IS NULL
        AND au.crm_role IN ('sales', 'manager')
        AND coalesce(array_length(au.mes_roles, 1), 0) = 0
        AND EXISTS (SELECT 1 FROM crm_customers c WHERE c.account_owner_id = au.user_id)
    SQL
  end

  def down
    remove_column :account_users, :in_sales_rank
  end
end
