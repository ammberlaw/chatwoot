# 侧栏角标：当前用户「该动手」的会话数。
#   unattended = Conversation.unattended：还没人回过的，外加回过之后客户又发了、
#                还在等回复的（waiting_since 不为空）。和「未处理」视图共用同一个 scope——
#                之前这里只写了 first_reply_created_at IS NULL，生产上角标 41、
#                点进列表 86，差的 45 条全是「回过又被客户催」的。
#   needs_attention = 上面这些 + 有未读新消息的（去重，不重复计数），挂在「会话」分组上
# 可见范围复用 ConversationFinder 那套（管理员只算自己名下收件箱，业务员走 Visibility），
# 所以角标点进去数得上，不会出现「角标有 3 点进去却是空的」。
class Api::V1::Accounts::Conversations::AttentionCountsController < Api::V1::Accounts::BaseController
  def index
    scope = ConversationFinder.new(Current.user, { status: 'open' }).visible_scope
    render json: {
      unattended: scope.unattended.count,
      needs_attention: scope.where(unattended_or_unread).count
    }
  end

  private

  # 没人回过 OR 客户还在等 OR 有未读来信
  def unattended_or_unread
    table = Conversation.arel_table
    table[:first_reply_created_at].eq(nil)
                                  .or(table[:waiting_since].not_eq(nil))
                                  .or(Conversation.unread_messages_count_arel.gt(0))
  end
end
