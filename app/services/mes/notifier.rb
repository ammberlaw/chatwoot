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

    private

    # 单次广播到全部收件人的 pubsub_token；前端收到即各自拉取自己的未读数/列表。
    def push(account, users)
      tokens = users.map(&:pubsub_token).compact.uniq
      return if tokens.blank?

      ActionCableBroadcastJob.perform_later(tokens, EVENT, { account_id: account.id })
    end
  end
end
