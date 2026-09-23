# 销假（撤销已通过的考勤类审批）需要两条链路：
#
# 1. crm_attendance_records.approval_request_id —— 考勤记录是哪张审批单写的。
#    原来只有 source='approval' 这个笼统标记，同一天若被多张单写过（先请假、后补卡）
#    就分不清该回滚哪张，销假只能靠日期猜，必然误伤。
#
# 2. oa_approval_requests.revokes_request_id —— 销假单指向被销的原单（自关联）。
#    销假本身走审批（原审批人同意才生效），所以它是一张独立的单，不是原单上的一个开关。
class AddRevokeSupportToApprovals < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_attendance_records, :approval_request_id, :bigint
    add_index :crm_attendance_records, [:account_id, :approval_request_id],
              name: 'idx_attendance_by_approval'

    add_column :oa_approval_requests, :revokes_request_id, :bigint
    add_index :oa_approval_requests, [:account_id, :revokes_request_id],
              name: 'idx_approval_revokes'
  end
end
