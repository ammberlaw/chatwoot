# 给指定成员发一条团队沟通单聊消息（管理层 → 成员的系统通知，如绩效下发 / 打分结果）。
# 复用已有的单聊去重逻辑；失败只记日志，绝不阻断主业务流程。
class Chat::NotifyService
  def initialize(account:, sender:)
    @account = account
    @sender = sender
  end

  # target_id：接收通知的成员 user_id。content：消息正文。
  #
  # ref：这条通知指向的单据，消息下面会渲染成一张可点的卡片，点了直接跳到那张单
  #（复用消息本来就有的「引用单据」机制，前端 openRef）。形如：
  #   { type: 'kpi_sheet', id: 12, label: '考核表', title: '2026年9月业务绩效考核方案',
  #     subtitle: '邹梅 提交 · 待打分' }
  # 不传就是一条纯文字通知，和原来一样——收到的人还得自己去翻是哪一张单。
  def notify(target_id, content, ref: nil)
    return if @sender.nil? || target_id.blank? || target_id == @sender.id

    conversation = Chat::CreateConversationService
                   .new(account: @account, creator: @sender)
                   .find_or_create_direct(target_id)
    conversation.messages.create!(
      { account_id: @account.id, sender_id: @sender.id, content: content }.merge(ref_columns(ref))
    )
    conversation.update!(last_message_at: Time.current)
    conversation
  rescue StandardError => e
    Rails.logger.error("[Chat::Notify] sender=#{@sender&.id} to=#{target_id}: #{e.class} #{e.message}")
    nil
  end

  private

  # label/title/subtitle 存快照：单据改了名、甚至被删了，历史通知卡片上的文字照旧
  #（跟引用客户/订单那套一个道理）。
  def ref_columns(ref)
    return {} if ref.blank? || ref[:type].blank? || ref[:id].blank?

    { ref_type: ref[:type].to_s, ref_id: ref[:id],
      ref_snapshot: { 'label' => ref[:label], 'title' => ref[:title], 'subtitle' => ref[:subtitle],
                      'customer_id' => ref[:customer_id] }.compact }
  end
end
