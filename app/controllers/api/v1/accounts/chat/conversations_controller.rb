class Api::V1::Accounts::Chat::ConversationsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_conversation, only: [:show, :read]

  def index
    @conversations = Current.account.chat_conversations
                            .for_user(current_user.id)
                            .includes(participants: :user)
                            .recent
  end

  def show; end

  def create
    service = Chat::CreateConversationService.new(account: Current.account, creator: current_user)
    @conversation = if params[:kind] == 'group'
                      service.create_group(name: params[:name].presence || '群聊', user_ids: params[:user_ids])
                    else
                      service.find_or_create_direct(params[:user_id])
                    end
    render :show
  end

  # 标记已读到最新一条。
  def read
    last = @conversation.messages.maximum(:id)
    @conversation.participants.where(user_id: current_user.id)
                 .update_all(last_read_message_id: last, last_read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    head :ok
  end

  private

  def fetch_conversation
    @conversation = Current.account.chat_conversations.for_user(current_user.id).find(params[:id])
  end

  def check_authorization
    authorize(Chat::Conversation)
  end
end
