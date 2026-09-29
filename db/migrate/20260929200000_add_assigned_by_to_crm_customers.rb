# 客户分配人：谁把这个客户分给了现负责人。业务员回复该客户时自动抄送分配人的邮箱留档
# （与「邮件分发」的强制抄送同一套机制，见 EmailsController#forced_cc_for）。
class AddAssignedByToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_customers, :assigned_by_id, :bigint
  end
end
