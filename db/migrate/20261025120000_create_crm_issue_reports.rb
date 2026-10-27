# 用户在 AI 助手里提交的「这是不是 bug」问题单。
#
# 关键不在用户写了什么，而在**提交那一刻的现场**：单号、状态、诊断跑出来的阻碍、
# 该谁动、通知发没发、提交人的角色。没有现场，一句「出不了货」和发微信截图没区别，
# 修的人还得从头考古一遍（2026-10-23/24 那几个 bug 就是这么一条条查出来的）。
class CreateCrmIssueReports < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_issue_reports do |t|
      t.bigint :account_id, null: false
      t.bigint :reporter_id, null: false
      # 用户原话
      t.text :body, null: false
      # 指向的单据（可空：也可能是「这个功能在哪」这类不挂单的问题）
      t.string :subject_type
      t.bigint :subject_id
      t.string :subject_no
      t.string :action_type
      # 提交那一刻的完整现场（诊断结论 + 该谁动 + 通知状态 + 提交人权限）
      t.jsonb :context, null: false, default: {}
      # new 待看 / ack 已确认 / fixed 已修 / wontfix 不是问题
      t.string :status, null: false, default: 'new'
      t.text :resolution
      t.datetime :resolved_at
      t.bigint :resolved_by_id
      t.timestamps
    end

    add_index :crm_issue_reports, [:account_id, :status, :created_at],
              name: 'index_crm_issue_reports_on_account_status_created'
    add_index :crm_issue_reports, [:subject_type, :subject_id]
    add_index :crm_issue_reports, :reporter_id
  end
end
