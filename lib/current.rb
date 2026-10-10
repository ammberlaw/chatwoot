module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # 会话列表序列化时每行都要判断「我钉过没有」，一次请求只查一次（见 ConversationPin.pinned?）
  thread_mattr_accessor :pinned_conversation_ids
  # 生产任务单列表序列化时每行都要给用料配价，标准价表和「最近采购价」是全局的，
  # 一次请求只算一次（见 Mes::MaterialPriceResolver）。25 行一页不这么做就是 25 次全表扫。
  thread_mattr_accessor :material_price_catalog

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.pinned_conversation_ids = nil
    Current.material_price_catalog = nil
  end
end
