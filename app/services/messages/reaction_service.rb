# 表情回应（WhatsApp 的 ❤️👍 那种）。
#
# 回应不是一条独立消息，而是挂在「被回应的那条」上：WhatsApp 的语义是每人对同一条
# 消息最多一个回应——再发一个是替换，发空字符串是撤销。这里按 (谁, 谁的 id) 去重，
# 照这个语义来。
#
# 存在被回应消息的 content_attributes['reactions'] 里，不另建表：消息一保存，
# after_update_commit 就把整条推给前端，实时同步和历史回看都白拿。
#
# 入站（客户回应我们）和出站（业务员在 CRM 里回应客户）都走这里，保证两边
# 落库形状一致。
class Messages::ReactionService
  CONTACT = 'contact'.freeze
  AGENT = 'agent'.freeze

  # emoji 为空 = 撤销该人的回应。source_id 是这条回应在 WhatsApp 上的 id，
  # 出站时用来做撤销/替换，没有也不影响显示。
  pattr_initialize [:message!, :actor!, :actor_id!, { emoji: nil, actor_name: nil, source_id: nil }]

  def perform
    message.with_lock do
      others = current_list.reject { |r| same_actor?(r) }
      others << entry if emoji.present?
      write(others)
    end
    message
  end

  private

  def current_list
    Array(message.content_attributes['reactions'])
  end

  def same_actor?(row)
    row['actor'].to_s == actor.to_s && row['actor_id'].to_s == actor_id.to_s
  end

  def entry
    {
      'emoji' => emoji,
      'actor' => actor.to_s,
      'actor_id' => actor_id,
      'actor_name' => actor_name.presence,
      'source_id' => source_id.presence,
      'at' => Time.current.to_i
    }.compact
  end

  # 一条回应都不剩就把键删掉，别在 content_attributes 里留个空数组。
  def write(list)
    attrs = message.content_attributes.dup
    list.empty? ? attrs.delete('reactions') : attrs['reactions'] = list
    message.update!(content_attributes: attrs)
  end
end
