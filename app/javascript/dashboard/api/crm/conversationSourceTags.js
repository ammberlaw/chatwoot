/* global axios */
import ApiClient from '../ApiClient';

// 会话「来源」标签(复用客户来源选项),打在会话上。
class ConversationSourceTagsAPI extends ApiClient {
  constructor() {
    super('crm/conversation_source_tags', { accountScoped: true });
  }

  update(conversationId, tags) {
    return axios.patch(`${this.url}/${conversationId}`, { tags });
  }
}

export default new ConversationSourceTagsAPI();
