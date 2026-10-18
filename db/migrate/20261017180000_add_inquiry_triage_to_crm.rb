# 新询盘 AI 初筛（Crm::InquiryTriageJob）要两样东西：
# · 账号级开关——这功能会自动调模型花钱，必须显式打开，默认关着；
# · 每封信的初筛时间——重跑收信、客户连发几封时靠它去重，不重复花钱、不重复建档。
class AddInquiryTriageToCrm < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_ai_settings, :inquiry_triage_enabled, :boolean, default: false, null: false
    add_column :crm_emails, :ai_triaged_at, :datetime
    add_index :crm_emails, [:account_id, :ai_triaged_at]
  end
end
