# 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定入口。
# 支持一人绑多个号:每个号一个独立收件箱,只有本人(+管理员)可见其会话。
class Api::V1::Accounts::Crm::WhatsappWebController < Api::V1::Accounts::Crm::BaseController
  # 我名下所有 WhatsApp 号(不打桥,读库里缓存的连接状态)。
  def index
    render json: my_inboxes.map { |inbox| serialize(inbox) }
  end

  # 新增一个号:建收件箱 + 起桥会话,返回该号的 QR。
  def create
    inbox = create_personal_inbox
    state = bridge.connect(inbox.channel.session_key)
    render json: serialize(inbox, state)
  end

  # 开始/恢复某个号的绑定,返回最新 QR / 连接结果。
  def connect
    inbox = target_inbox
    return head :not_found unless inbox

    state = bridge.connect(inbox.channel.session_key)
    render json: serialize(inbox, state)
  end

  # 轮询某个号的实时状态(直接问桥)。
  def status
    inbox = target_inbox
    return render json: { status: 'disconnected' } unless inbox

    state = bridge.status(inbox.channel.session_key)
    render json: serialize(inbox, state)
  end

  # 解绑某个号:桥登出并清凭证,收件箱保留(历史/客户留存)。
  def logout
    inbox = target_inbox
    return head :ok unless inbox

    bridge.logout(inbox.channel.session_key)
    inbox.channel.update!(connection_status: 'disconnected')
    render json: serialize(inbox, { 'status' => 'disconnected' })
  end

  private

  def bridge
    @bridge ||= Whatsapp::BaileysBridgeClient.new
  end

  def my_inboxes
    Current.account.inboxes
           .where(channel_type: 'Channel::WhatsappWeb')
           .joins(:inbox_members)
           .where(inbox_members: { user_id: current_user.id })
           .order(:id)
  end

  # 按 inbox_id 定位且校验归属(必须是本人的 WhatsApp Web 收件箱)。
  def target_inbox
    my_inboxes.find_by(id: params[:inbox_id])
  end

  def create_personal_inbox
    ActiveRecord::Base.transaction do
      channel = Current.account.whatsapp_web_channels.create!
      seq = my_inboxes.count + 1
      inbox = Current.account.inboxes.create!(name: "#{current_user.name} 的 WhatsApp #{seq}", channel: channel)
      inbox.inbox_members.create!(user: current_user)
      inbox
    end
  end

  def serialize(inbox, state = nil)
    channel = inbox&.channel
    {
      inbox_id: inbox&.id,
      name: inbox&.name,
      phone_number: channel&.phone_number,
      status: state ? state['status'] : channel&.connection_status || 'disconnected',
      qr: state && state['qr']
    }
  end
end
