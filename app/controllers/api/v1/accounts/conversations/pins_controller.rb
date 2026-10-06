# 会话置顶：每人钉自己的，互不影响。钉住的会话在列表里排在最前（见 ConversationFinder#pin_first）。
# 上限 MAX_PER_USER——不限的话钉久了顶上堆一长串，跟没钉一样。
class Api::V1::Accounts::Conversations::PinsController < Api::V1::Accounts::Conversations::BaseController
  def create
    if at_limit?
      return render json: { error: "最多只能置顶 #{ConversationPin::MAX_PER_USER} 条会话，先取消几个再钉" },
                    status: :unprocessable_entity
    end

    ConversationPin.find_or_create_by!(account_id: Current.account.id, user_id: Current.user.id,
                                       conversation_id: @conversation.id)
    render json: { pinned: true }
  end

  def destroy
    my_pins.where(conversation_id: @conversation.id).delete_all
    render json: { pinned: false }
  end

  private

  def my_pins
    ConversationPin.where(account_id: Current.account.id, user_id: Current.user.id)
  end

  def at_limit?
    my_pins.where.not(conversation_id: @conversation.id).count >= ConversationPin::MAX_PER_USER
  end
end
