# 展会邀请函落地页（公开、免登录）：客户从邀请邮件点链接进来 → 看到带展位号的邀请函 → 在线确认到访。
# GET landing：展示邀请函；若邀约处于「已邀约」则自动推进到「已互动」（客户点开链接即算互动）。
# POST confirm：回填客户填写的到访信息并推进到「已接受」，再渲染已确认状态。
class Crm::ExhibitionInvitesController < PublicController
  layout false

  before_action :fetch_invite

  def landing
    render :not_found, status: :not_found and return if @invite.nil?

    @invite.advance_to!('interacted') if @invite.stage == 'invited'
    @confirmed = @invite.stage == 'accepted'
  end

  def confirm
    render :not_found, status: :not_found and return if @invite.nil?

    @invite.assign_attributes(reply_params)
    @invite.advance_to!('accepted')
    @confirmed = true
    render :landing
  end

  private

  def fetch_invite
    @invite = Crm::ExhibitionInvite.find_by(confirm_token: params[:token])
    @exhibition = @invite&.exhibition
  end

  def reply_params
    params.permit(:reply_company, :reply_name, :reply_contact, :reply_products, :reply_visit_date, :reply_note)
  end
end
