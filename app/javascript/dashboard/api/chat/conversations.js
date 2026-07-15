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

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  removeParticipant(id, userId) {
    return axios.post(`${this.url}/${id}/remove_participant`, {
      user_id: userId,
    });
  }

  markRead(id) {
    return axios.post(`${this.url}/${id}/read`);
  }

  messages(id, after = 0) {
    return axios.get(`${this.url}/${id}/messages?after=${after}`);
  }

  send(id, content, files = []) {
    if (!files.length) {
      return axios.post(`${this.url}/${id}/messages`, { content });
    }
    const fd = new FormData();
    fd.append('content', content || '');
    files.forEach(f => fd.append('files[]', f));
    return axios.post(`${this.url}/${id}/messages`, fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new ChatConversationAPI();
