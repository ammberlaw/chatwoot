/* global axios */
import ApiClient from './ApiClient';

class SearchAPI extends ApiClient {
  constructor() {
    super('search', { accountScoped: true });
  }

  get({ q }) {
    return axios.get(this.url, {
      params: {
        q,
      },
    });
  }

  contacts({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/contacts`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }

  conversations({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/conversations`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }

  // conversationId（会话的 display_id）＝ 只在这一张会话里翻聊天记录；
  // 传了它后端就不卡 3 个月时间窗（见 SearchService#message_base_query）。
  messages({ q, page = 1, since, until, from, inboxId, conversationId }) {
    return axios.get(`${this.url}/messages`, {
      params: {
        q,
        page: page,
        since,
        until,
        from,
        inbox_id: inboxId,
        conversation_id: conversationId,
      },
    });
  }

  articles({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/articles`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }
}

export default new SearchAPI();
