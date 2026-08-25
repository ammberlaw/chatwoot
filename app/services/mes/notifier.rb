# MES 站内通知统一出口：落库（持久化，供未读角标/历史）+ ActionCable 实时下发。
# 所有生产流转/审批/接单埋点都调这里，收件人以 user_id 传入（自动去重、去空、去非本账号成员）。
class Mes::Notifier
  EVENT = 'mes.notification.created'.freeze

  class << self
    # recipients: user_id 或其数组。order: 关联生产订单（可空）。
    def notify(account:, recipients:, kind:, title:, body: nil, order: nil)
      user_ids = Array(recipients).compact.uniq
      return [] if user_ids.blank?

      users = account.users.where(id: user_ids)
      return [] if users.blank?

      records = users.map do |user|
        account.mes_notifications.create!(
          recipient_id: user.id, production_order_id: order&.id, kind: kind, title: title, body: body
        )
      end
      push(account, users)
      records
    end

    # 办结：把指定 kind 的「待办」通知标记已读（从「待处理」清走）。
    # 在真正的办结动作（审批通过/驳回、确认BOM、接单、出库等）时调用，与「点开查看」区分开——
    # 待办不因被查看而消失，只因动作真正完成才消。
    # 定位方式二选一/并用：order（挂生产订单的待办）、title_like（现货出库等不挂订单的待办，按单号匹配标题）。
    # recipients 省略=符合条件的全销（审批链多级、多个阶段负责人）。
    def resolve(account:, kinds:, order: nil, title_like: nil, recipients: nil)
      scope = account.mes_notifications.where(kind: Array(kinds), read_at: nil)
      scope = scope.where(production_order_id: order.id) if order
      scope = scope.where('title ILIKE ?', "%#{title_like}%") if title_like
      scope = scope.where(recipient_id: Array(recipients)) if recipients
      scope.update_all(read_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    # 单次广播到全部收件人的 pubsub_token；前端收到即各自拉取自己的未读数/列表。
    def push(account, users)
      tokens = users.map(&:pubsub_token).compact.uniq
      return if tokens.blank?

      ActionCableBroadcastJob.perform_later(tokens, EVENT, { account_id: account.id })
    end
  end
end
