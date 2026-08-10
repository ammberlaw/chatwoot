class AddPayoutMarkingToCrmSheets < ActiveRecord::Migration[7.1]
  def change
    # 绩效表：财务对总经理归档(ARCHIVED)的表标记「已发放」；金额用系统已算好的 actual_payout_micros。
    add_column :crm_kpi_sheets, :paid_at, :datetime
    add_column :crm_kpi_sheets, :paid_by_id, :bigint

    # 提成表：财务对主管通过(APPROVED)的表标记「已发放」，并填实发提成金额(系统不算)+备注。
    add_column :crm_commission_sheets, :paid_at, :datetime
    add_column :crm_commission_sheets, :paid_by_id, :bigint
    add_column :crm_commission_sheets, :paid_amount_micros, :bigint
    add_column :crm_commission_sheets, :paid_note, :text
  end
end
