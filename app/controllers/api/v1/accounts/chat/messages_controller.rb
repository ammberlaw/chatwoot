class Api::V1::Accounts::Chat::MessagesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_conversation

  RESULTS_PER_PAGE = 50

  def index
    @messages = @conversation.messages.includes(:sender, reply_to: :sender).order(id: :asc)
                             .where('id > ?', params[:after].to_i)
                             .limit(RESULTS_PER_PAGE)
    mark_read
  end

  REF_TYPES = %w[customer sales_order opportunity].freeze

  def create
    @message = @conversation.messages.new(
      account_id: Current.account.id, sender_id: current_user.id, content: params[:content],
      mentioned_ids: normalized_mentions, ref_type: ref_type, ref_id: ref_type && params[:ref_id].presence,
      ref_snapshot: ref_snapshot, reply_to_id: reply_to_id
    )
    @message.files.attach(params[:files]) if params[:files].present?
    @message.save!
    @conversation.update!(last_message_at: Time.current)
    Chat::EventBroadcaster.broadcast_message(@conversation, @message)
    mark_read
    render :show
  end

  # 转发：把本会话里选中的多条消息（含正文/附件/业务卡片）原样发到目标会话。
  # 附件复用原 blob（不重新上传）；目标会话必须是当前用户可见的会话。
  def forward
    target = Current.account.chat_conversations.for_user(current_user.id).find(params[:target_conversation_id])
    sources = @conversation.messages.where(id: Array(params[:message_ids]).map(&:to_i)).order(:id)
    return render json: { error: '请选择要转发的消息' }, status: :unprocessable_entity if sources.empty?

    forwarded = sources.map { |src| forward_one(src, target) }
    target.update!(last_message_at: Time.current)
    forwarded.each { |msg| Chat::EventBroadcaster.broadcast_message(target, msg) }
    render json: { count: forwarded.size, conversation_id: target.id }
  end

  private

  # 复制一条消息到目标会话（正文/业务卡片照搬，附件复用原 blob）。
  def forward_one(src, target)
    msg = target.messages.create!(
      account_id: Current.account.id, sender_id: current_user.id, content: src.content,
      ref_type: src.ref_type, ref_id: src.ref_id, ref_snapshot: src.ref_snapshot
    )
    src.files.each { |file| msg.files.attach(file.blob) }
    msg
  end

  # 引用回复：仅接受同会话内的消息 id，越权/脏数据置空。
  def reply_to_id
    id = params[:reply_to_id].presence
    return nil unless id

    @conversation.messages.where(id: id).exists? ? id : nil
  end

  # @提及：只保留仍在本会话中的成员，过滤越权/脏数据。
  def normalized_mentions
    ids = Array(params[:mentioned_ids]).map(&:to_i).uniq
    return [] if ids.empty?

    ids & @conversation.participants.pluck(:user_id)
  end

  def ref_type
    t = params[:ref_type].to_s
    REF_TYPES.include?(t) ? t : nil
  end

  # 卡片快照：发送时定格的标题/编号，前端渲染卡片用（点击跳转到对象详情）。
  def ref_snapshot
    return nil unless ref_type

    params[:ref_snapshot]&.permit(:title, :subtitle, :code)&.to_h.presence
  end

  def mark_read
    last = @conversation.messages.maximum(:id)
    @conversation.participants.where(user_id: current_user.id)
                 .update_all(last_read_message_id: last, last_read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def fetch_conversation
    @conversation = Current.account.chat_conversations.for_user(current_user.id).find(params[:conversation_id])
  end

  def check_authorization
    authorize(Chat::Conversation)
  end
end
