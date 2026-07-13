/* global axios */
import ApiClient from '../ApiClient';

class ChatConversationAPI extends ApiClient {
  constructor() {
    super('chat/conversations', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(payload) {
    return axios.post(this.url, payload);
  }

  markRead(id) {
    return axios.post(`${this.url}/${id}/read`);
  }

  messages(id, after = 0) {
    return axios.get(`${this.url}/${id}/messages?after=${after}`);
  }

  send(id, content) {
    return axios.post(`${this.url}/${id}/messages`, { content });
  }
}

export default new ChatConversationAPI();
