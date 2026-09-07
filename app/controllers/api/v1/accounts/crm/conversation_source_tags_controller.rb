# 给会话(WhatsApp 客户)打「来源」标签:复用客户来源选项(crm_option_items customer_source),
# 一个会话可多个,存在 conversation.additional_attributes['crm_source_tags']。
class Api::V1::Accounts::Crm::ConversationSourceTagsController < Api::V1::Accounts::Crm::BaseController
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
