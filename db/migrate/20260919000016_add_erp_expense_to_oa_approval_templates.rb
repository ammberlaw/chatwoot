# 标记「这类审批单是费用报销」，ERP 财务端据此筛出待打款的单。
# 不复用 cash_kind：cash_kind=reimburse 走的是部门备用金台账落账，与公司账户打款是两回事。
class AddErpExpenseToOaApprovalTemplates < ActiveRecord::Migration[7.1]
  def up
    add_column :oa_approval_templates, :erp_expense, :boolean, null: false, default: false

    # 已在用的报销模板自动勾上，免得上线后财务看到空列表以为没接通。
    execute <<~SQL.squish
      UPDATE oa_approval_templates
      SET erp_expense = TRUE
      WHERE cash_kind = 'reimburse' OR name LIKE '%报销%'
    SQL
  end

  def down
    remove_column :oa_approval_templates, :erp_expense
  end
end
