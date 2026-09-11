# 给会话(WhatsApp 客户)打「来源」标签:复用客户来源选项(crm_option_items customer_source),
# 一个会话可多个,存在 conversation.additional_attributes['crm_source_tags']。
class Api::V1::Accounts::Crm::ConversationSourceTagsController < Api::V1::Accounts::Crm::BaseController
  # 侧栏「客户来源」分组的角标：每个来源 code 下有多少条会话（按当前用户可见范围收口）。
  def counts
    scope = Conversations::PermissionFilterService.new(Current.account.conversations, current_user, Current.account).perform
    rows = scope.where("additional_attributes ? 'crm_source_tags'")
                .pluck(Arel.sql("additional_attributes -> 'crm_source_tags'"))
    render json: { payload: rows.flatten.tally }
  end

  def update
    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id]) ||
                   Current.account.conversations.find_by(id: params[:conversation_id])
    return head :not_found unless conversation

    tags = Array(params[:tags]).map(&:to_s).reject(&:blank?).uniq
    attrs = conversation.additional_attributes || {}
    attrs['crm_source_tags'] = tags
    conversation.update!(additional_attributes: attrs)
    render json: { conversation_id: conversation.display_id, tags: tags }
  end
end
