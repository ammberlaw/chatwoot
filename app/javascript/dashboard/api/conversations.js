/* global axios */
import ApiClient from './ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getLabels(conversationID) {
    return axios.get(`${this.url}/${conversationID}/labels`);
  }

  updateLabels(conversationID, labels) {
    return axios.post(`${this.url}/${conversationID}/labels`, { labels });
  }

  getUnreadCounts() {
    return axios.get(`${this.url}/unread_counts`);
  }

  // 侧栏角标：未处理数 + 「该动手」的会话数（未处理 or 有未读来信）。
  getAttentionCounts() {
    return axios.get(`${this.url}/attention_counts`);
  }
}

export default new ConversationApi();
