# 用户在 AI 助手里报上来的问题单（Crm::Agent::Tools::ReportIssue 存的）。
#
# 原来只有一条站内通知：刷过去就埋了，既没有清单也没法标「修好了」——生产上
# 攒了 8 条全是 new，最早那条放了一周多没人动。这页就是那份清单。
#
# 只给超管和副管：收通知的是这两档人，能看的也该是这两档。
class Api::V1::Accounts::Crm::IssueReportsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin
  before_action :fetch_report, only: [:update]

  def index
    scope = Current.account.crm_issue_reports.includes(:reporter, :resolved_by).recent_first
    scope = scope.where(status: params[:status]) if Crm::IssueReport::STATUSES.include?(params[:status].to_s)
    @reports = scope.limit(200)
    @counts = Current.account.crm_issue_reports.group(:status).count
  end

  # 改状态 / 写处理说明。标成已修复或不做时记下是谁、什么时候收的尾。
  def update
    status = params[:report][:status].to_s
    return render json: { error: '无效的状态' }, status: :unprocessable_entity if Crm::IssueReport::STATUSES.exclude?(status)

    @report.update!(status: status, resolution: params[:report][:resolution].to_s.strip.presence,
                    **closing_attrs(status))
    render :show
  end

  private

  # 回到「待查/已受理」就把收尾信息清掉——留着会让人以为还是修好的那一版。
  def closing_attrs(status)
    return { resolved_by_id: nil, resolved_at: nil } if %w[new ack].include?(status)

    { resolved_by_id: current_user.id, resolved_at: Time.current }
  end

  def fetch_report
    @report = Current.account.crm_issue_reports.find(params[:id])
  end

  def ensure_admin
    return if Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?

    render json: { error: '仅超级管理员或副管理员可查看问题反馈' }, status: :forbidden
  end
end
