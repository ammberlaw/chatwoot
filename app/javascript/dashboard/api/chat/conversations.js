/* global axios */
import ApiClient from '../ApiClient';

class ChatConversationAPI extends ApiClient {
  constructor() {
    super('chat/conversations', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  unreadTotal() {
    return axios.get(`${this.url}/unread_total`);
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

  transferOwner(id, userId) {
    return axios.post(`${this.url}/${id}/transfer_owner`, {
      user_id: userId,
    });
  }

  leave(id) {
    return axios.post(`${this.url}/${id}/leave`);
  }

  markRead(id) {
    return axios.post(`${this.url}/${id}/read`);
  }

  messages(id, after = 0) {
    return axios.get(`${this.url}/${id}/messages?after=${after}`);
  }

  // extra: { mentioned_ids: [], ref_type, ref_id, ref_snapshot: {title, subtitle, code}, reply_to_id }
  send(id, content, files = [], extra = {}) {
    const {
      mentioned_ids: mentionedIds = [],
      ref_type: refType,
      ref_id: refId,
      ref_snapshot: refSnapshot,
      reply_to_id: replyToId,
    } = extra;
    if (!files.length) {
      return axios.post(`${this.url}/${id}/messages`, {
        content,
        mentioned_ids: mentionedIds,
        ref_type: refType,
        ref_id: refId,
        ref_snapshot: refSnapshot,
        reply_to_id: replyToId,
      });
    }
    const fd = new FormData();
    fd.append('content', content || '');
    files.forEach(f => fd.append('files[]', f));
    mentionedIds.forEach(uid => fd.append('mentioned_ids[]', uid));
    if (replyToId) fd.append('reply_to_id', replyToId);
    if (refType) {
      fd.append('ref_type', refType);
      fd.append('ref_id', refId);
      Object.entries(refSnapshot || {}).forEach(([k, v]) =>
        fd.append(`ref_snapshot[${k}]`, v ?? '')
      );
    }
    return axios.post(`${this.url}/${id}/messages`, fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // 转发多条消息到目标会话。
  forward(id, messageIds, targetConversationId) {
    return axios.post(`${this.url}/${id}/messages/forward`, {
      message_ids: messageIds,
      target_conversation_id: targetConversationId,
    });
  }
}

export default new ChatConversationAPI();
