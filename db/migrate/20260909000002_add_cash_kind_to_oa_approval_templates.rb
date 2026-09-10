# 审批模板 → 备用金台账的联动开关，写法与既有 attendance_kind 一致：
# advance=备用金申请（通过后记一笔存入），reimburse=费用报销（通过后记一笔支出）。
class AddCashKindToOaApprovalTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :oa_approval_templates, :cash_kind, :string
  end
end
