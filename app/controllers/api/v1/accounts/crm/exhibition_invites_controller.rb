# 展会邀约记录操作：AI 生成邀请函 / 阶段流转（已邀约·已互动·谢绝）/ 移出名单。
# 客户「已接受」由公开落地页确认时置入，不在此手动设。
class Api::V1::Accounts::Crm::ExhibitionInvitesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_invite

  # AI 生成邀请函（不发送）：返回 { subject, body, confirm_url }，业务员可复制或转到写信发出。
  def compose
    subject, body = Crm::EmailAiService.new(account: Current.account).compose_invite(
      exhibition: @invite.exhibition,
      customer: @invite.customer,
      confirm_url: @invite.public_confirm_url
    )
    render json: { subject: subject, body: body, confirm_url: @invite.public_confirm_url }
  rescue Crm::EmailAiService::NotConfigured => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 阶段流转：invited（已邀约，发出邀请函后点）/ interacted（已互动）/ declined（谢绝）。
  def advance
    stage = params[:stage].to_s
    return render(json: { error: '无效阶段' }, status: :unprocessable_entity) unless Crm::ExhibitionInvite::STAGES.include?(stage)

    @invite.advance_to!(stage)
    render json: { id: @invite.id, stage: @invite.stage }
  end

  def destroy
    @invite.destroy!
    head :no_content
  end

  private

  def check_authorization
    authorize(Crm::ExhibitionInvite)
  end

  def fetch_invite
    @invite = scope_by_team_owner(Current.account.crm_exhibition_invites, column: :owner_id).find(params[:id])
  end
end
