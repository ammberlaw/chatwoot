class Api::V1::Accounts::Chat::MessagesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_conversation

  RESULTS_PER_PAGE = 50

  def index
    @messages = @conversation.messages.includes(:sender).order(id: :asc)
                             .where('id > ?', params[:after].to_i)
                             .limit(RESULTS_PER_PAGE)
    mark_read
  end

  def create
    @message = @conversation.messages.create!(
      account_id: Current.account.id, sender_id: current_user.id, content: params[:content]
    )
    @conversation.update!(last_message_at: Time.current)
    mark_read
    render :show
  end

  private

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
