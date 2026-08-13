# 单据级「退回上一环节」控制器动作（横切采购/入库/领料/报工…）。
# 各 include 的控制器须实现 returnable_record（按 params[:id] 载入本资源）
# 与 render_returnable(record)（渲染该资源 show 视图）。
module Api::V1::Accounts::Mes::DocumentReturnable
  extend ActiveSupport::Concern

  # 退回上一环节：填原因，标记单据「已退回」并通知上游板块负责人。
  def return_document
    reason = params[:reason].to_s.strip
    return render json: { error: '请填写退回原因' }, status: :unprocessable_entity if reason.blank?

    record = returnable_record
    record.return_to_upstream!(actor: current_user, reason: reason)
    render_returnable(record)
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 重新激活：解决当前退回，单据回到可继续处理状态。
  def reactivate
    record = returnable_record
    record.reactivate!(actor: current_user)
    render_returnable(record)
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
