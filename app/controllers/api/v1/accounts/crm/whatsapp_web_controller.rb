# 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定入口。
# 每个业务员最多一个个人号收件箱，只有本人(+管理员)可见其会话。
class Api::V1::Accounts::Crm::WhatsappWebController < Api::V1::Accounts::Crm::BaseController
  # 当前状态(不打桥，读库里缓存的连接状态)。
  def show
    render json: serialize(my_inbox)
  end

  # 开始/恢复绑定：确保有收件箱，然后让桥起会话，返回 QR。
  def connect
    inbox = my_inbox || create_personal_inbox
    state = bridge.connect(inbox.channel.session_key)
    render json: serialize(inbox, state)
  end

  # 轮询实时状态(直接问桥，拿最新 QR / 连接结果)。
  def status
    inbox = my_inbox
    return render json: { status: 'disconnected' } unless inbox

    state = bridge.status(inbox.channel.session_key)
    render json: serialize(inbox, state)
  end

  # 解绑：桥登出并清凭证，收件箱保留(历史消息/客户留存)，仅清连接态与号码。
  def logout
    inbox = my_inbox
    return head :ok unless inbox

    bridge.logout(inbox.channel.session_key)
    inbox.channel.update!(connection_status: 'disconnected')
    render json: serialize(inbox, { 'status' => 'disconnected' })
  end

  private

  def bridge
    @bridge ||= Whatsapp::BaileysBridgeClient.new
  end

  def my_inbox
    @my_inbox ||= Current.account.inboxes
                         .where(channel_type: 'Channel::WhatsappWeb')
                         .joins(:inbox_members)
                         .find_by(inbox_members: { user_id: current_user.id })
  end

  def create_personal_inbox
    ActiveRecord::Base.transaction do
      channel = Current.account.whatsapp_web_channels.create!
      inbox = Current.account.inboxes.create!(name: "#{current_user.name} 的 WhatsApp", channel: channel)
      inbox.inbox_members.create!(user: current_user)
      @my_inbox = inbox
    end
    @my_inbox
  end

  def serialize(inbox, state = nil)
    channel = inbox&.channel
    {
      inbox_id: inbox&.id,
      phone_number: channel&.phone_number,
      status: state ? state['status'] : channel&.connection_status || 'disconnected',
      qr: state && state['qr']
    }
  end
end
