class Api::V1::Accounts::Chat::ConversationsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_conversation, only: [:show, :read, :update, :remove_participant, :transfer_owner, :leave]
  before_action :ensure_group_owner, only: [:update, :remove_participant, :transfer_owner]

  def index
    @conversations = Current.account.chat_conversations
                            .for_user(current_user.id)
                            .includes(participants: :user)
                            .recent
  end

  def show; end

  def create
    if params[:kind] == 'group'
      return render json: { error: '建群需要填写群公告' }, status: :unprocessable_entity if params[:announcement].blank?

      @conversation = create_service.create_group(name: params[:name].presence || '群聊',
                                                  announcement: params[:announcement],
                                                  user_ids: params[:user_ids])
      post_announcement_message
    else
      @conversation = create_service.find_or_create_direct(params[:user_id])
    end
    render :show
  end

  # 群主编辑群名/群公告；新公告像微信一样推送一条消息到群里。
  def update
    announcement_changed = params[:announcement].present? && params[:announcement] != @conversation.announcement
    @conversation.update!(params.permit(:name, :announcement))
    post_announcement_message if announcement_changed
    render :show
  end

  # 群主踢人（不能移除自己）。
  def remove_participant
    return render json: { error: '群主不能移除自己' }, status: :unprocessable_entity if params[:user_id].to_i == current_user.id

    @conversation.participants.where(user_id: params[:user_id]).destroy_all
    render :show
  end

  # 群主转让（像微信）：只能转给现有群成员；转让后原群主变普通成员。
  def transfer_owner
    target_id = params[:user_id].to_i
    return render json: { error: '只能转让给群成员' }, status: :unprocessable_entity unless @conversation.participants.exists?(user_id: target_id)

    @conversation.update!(creator_id: target_id)
    target_name = Current.account.users.find_by(id: target_id)&.name
    post_system_message("【群主变更】#{current_user.name} 将群主转让给 #{target_name}")
    render :show
  end

  # 退群：群里还有其他成员时，群主必须先转让群主才能退。
  def leave
    return render json: { error: '仅群聊支持退群' }, status: :unprocessable_entity unless @conversation.kind == 'group'

    if @conversation.creator_id == current_user.id && @conversation.participants.where.not(user_id: current_user.id).exists?
      return render json: { error: '群主需先转让群主才能退群' }, status: :unprocessable_entity
    end

    @conversation.participants.where(user_id: current_user.id).destroy_all
    head :ok
  end

  # 标记已读到最新一条。
  def read
    last = @conversation.messages.maximum(:id)
    @conversation.participants.where(user_id: current_user.id)
                 .update_all(last_read_message_id: last, last_read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    head :ok
  end

  private

  def create_service
    @create_service ||= Chat::CreateConversationService.new(account: Current.account, creator: current_user)
  end

  def fetch_conversation
    @conversation = Current.account.chat_conversations.for_user(current_user.id).find(params[:id])
  end

  def ensure_group_owner
    return if @conversation.kind == 'group' && @conversation.creator_id == current_user.id

    render json: { error: '仅群主可执行该操作' }, status: :forbidden
  end

  def post_announcement_message
    post_system_message("【群公告】\n#{@conversation.announcement}")
  end

  def post_system_message(content)
    @conversation.messages.create!(account_id: Current.account.id, sender_id: current_user.id, content: content)
    @conversation.update!(last_message_at: Time.current)
  end

  def check_authorization
    authorize(Chat::Conversation)
  end
end
