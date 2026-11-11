# 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定入口。
# 支持一人绑多个号:每个号一个独立收件箱,只有本人(+管理员)可见其会话。
class Api::V1::Accounts::Crm::WhatsappWebController < Api::V1::Accounts::Crm::BaseController
  # 我名下所有 WhatsApp 号(不打桥,读库里缓存的连接状态)。
  # 列表：状态以**桥接实况**为准，并把变化回写进库。
  # 原来只读库里存的 connection_status——桥接那边掉了会话（重启后凭据没了、手机上退了登录）
  # 它不会知道，于是界面一直显示「已连接」，人以为能收发、实际早就断了。
  def index
    live = bridge.sessions_status
    inboxes = my_inboxes.to_a
    reconcile_connection_status(inboxes, live) if live.present?
    render json: inboxes.map { |inbox| serialize(inbox, live_state(inbox, live)) }
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

  # 输入手机号直接开聊(对齐手机 WhatsApp:不需要对方先加好友,也不需要先建联系人)。
  # 先问桥这个号注册没注册——没注册的话发过去石沉大海,不如当场拦下。
  # 已经聊过的号不重复建会话,直接把已有的那条返回去。
  def start_chat
    inbox = target_inbox
    return head :not_found unless inbox

    phone = params[:phone].to_s.gsub(/\D/, '')
    return render json: { error: '请填写手机号(含国家码,如 8613800138000)' }, status: :unprocessable_entity if phone.blank?

    checked = bridge.check_number(inbox.channel.session_key, phone)
    return render json: { error: '这个号码没有注册 WhatsApp' }, status: :unprocessable_entity unless checked['exists']

    conversation = open_or_create_chat(inbox, checked['jid'], phone, params[:name])
    render json: { conversation_id: conversation.display_id, contact_name: conversation.contact.name }
  rescue Whatsapp::BaileysBridgeClient::BridgeError => e
    render json: { error: "查询号码失败:#{e.message}" }, status: :unprocessable_entity
  end

  # 解绑某个号:桥登出并清凭证,收件箱保留(历史/客户留存)。
  def logout
    inbox = target_inbox
    return head :ok unless inbox

    bridge.logout(inbox.channel.session_key)
    inbox.channel.update!(connection_status: 'disconnected')
    render json: serialize(inbox, { 'status' => 'disconnected' })
  end

  # 只移除从未绑定号码、没有历史数据的空收件箱。解绑仍保留历史。
  def destroy
    inbox = target_inbox
    return head :not_found unless inbox

    return render json: { error: '这个号已有绑定或历史记录，请使用「解绑」保留历史。' }, status: :unprocessable_entity unless removable_inbox?(inbox)
    return render json: { error: '这个号已连接，请先解绑。' }, status: :unprocessable_entity if bridge.status(inbox.id)['status'] == 'open'

    bridge.logout(inbox.id)
    inbox.destroy!
    head :ok
  rescue Whatsapp::BaileysBridgeClient::BridgeError
    render json: { error: '暂时无法连接 WhatsApp 服务，请稍后重试移除。' }, status: :unprocessable_entity
  end

  private

  def removable_inbox?(inbox)
    inbox.channel.phone_number.blank? && [inbox.conversations, inbox.contact_inboxes, inbox.messages].none?(&:exists?)
  end

  def bridge
    @bridge ||= Whatsapp::BaileysBridgeClient.new
  end

  # 会话按 JID 定位(与收信同口径),已有的复用、没有的建。联系人名字没填就用号码占位,
  # 等对方回消息带来 pushName 时会自动改成真名(见 IncomingMessageWhatsappWebService)。
  def open_or_create_chat(inbox, jid, phone, name)
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: jid,
      inbox: inbox,
      contact_attributes: { name: name.presence || phone, phone_number: "+#{phone}" }
    ).perform
    contact_inbox.conversations.where.not(status: :resolved).last ||
      ::Conversation.create!(
        account_id: inbox.account_id, inbox_id: inbox.id,
        contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id
      )
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

  # 桥接拿得到实况时才覆盖；拿不到（桥接不可达）就返回 nil，由 serialize 回落到库里的值——
  # 总比把一屏号全标成掉线、让人白跑一趟扫码强。
  def live_state(inbox, live)
    return nil if live.blank?

    key = inbox.channel.session_key.to_s
    { 'status' => live[key] || 'disconnected' }
  end

  # 实况与库里不一致就回写：别的地方（发送前的校验、看板）读的还是这一列。
  def reconcile_connection_status(inboxes, live)
    inboxes.each do |inbox|
      actual = live[inbox.channel.session_key.to_s] || 'disconnected'
      next if inbox.channel.connection_status == actual

      inbox.channel.update!(connection_status: actual)
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
