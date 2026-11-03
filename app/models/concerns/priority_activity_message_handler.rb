module PriorityActivityMessageHandler
  extend ActiveSupport::Concern

  private

  def priority_change_activity(user_name)
    old_priority, new_priority = previous_changes.values_at('priority')[0]
    return unless priority_change?(old_priority, new_priority)

    user = Current.executed_by.instance_of?(AutomationRule) ? I18n.t('automation.system_name') : user_name
    content = build_priority_change_content(user, old_priority, new_priority)

    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end

  def priority_change?(old_priority, new_priority)
    old_priority.present? || new_priority.present?
  end

  def build_priority_change_content(user_name, old_priority = nil, new_priority = nil)
    change_type = get_priority_change_type(old_priority, new_priority)

    I18n.t("conversations.activity.priority.#{change_type}", user_name: user_name,
                                                             new_priority: priority_label(new_priority),
                                                             old_priority: priority_label(old_priority))
  end

  # 优先级的值原先直接把库里的枚举塞进句子，于是中文句子里夹着英文
  # （「John Miller 将优先级设置为 urgent」，用户 2026-11-03 指出）。
  # 没配译名的值原样返回，不会因为多了个新枚举就显示成空。
  def priority_label(value)
    return value if value.blank?

    I18n.t("conversations.activity.priority.levels.#{value}", default: value)
  end

  def get_priority_change_type(old_priority, new_priority)
    case [old_priority.present?, new_priority.present?]
    when [true, true] then 'updated'
    when [false, true] then 'added'
    when [true, false] then 'removed'
    end
  end
end
