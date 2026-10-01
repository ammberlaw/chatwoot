# 侧栏角标：当前用户「该动手」的会话数。
#   unattended = 客户发来后还没人回过的（与「未处理」视图同口径）
#   needs_attention = 上面这些 + 有未读新消息的（去重，不重复计数），挂在「会话」分组上
# 可见范围复用 ConversationFinder 那套（管理员只算自己名下收件箱，业务员走 Visibility），
# 所以角标点进去数得上，不会出现「角标有 3 点进去却是空的」。
class Api::V1::Accounts::Conversations::AttentionCountsController < Api::V1::Accounts::BaseController
  def index
    scope = ConversationFinder.new(Current.user, { status: 'open' }).visible_scope
    unattended = scope.where(first_reply_created_at: nil)
    render json: {
      unattended: unattended.count,
      needs_attention: scope.where(unattended_or_unread).count
    }
  end

  private

  # 没人回过 OR 有未读来信
  def unattended_or_unread
    Conversation.arel_table[:first_reply_created_at].eq(nil)
                .or(Conversation.unread_messages_count_arel.gt(0))
  end
end
