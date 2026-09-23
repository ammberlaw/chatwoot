/* global axios */
import ApiClient from '../ApiClient';

class CredentialsAPI extends ApiClient {
  constructor() {
    super('crm/credentials', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  createEntry(payload) {
    return axios.post(this.url, { credential: payload });
  }

  updateEntry(id, payload) {
    return axios.patch(`${this.url}/${id}`, { credential: payload });
  }

  deleteEntry(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // 取明文密码：每次调用都会在后端记一条查看记录。
  reveal(id, logAction = 'reveal') {
    return axios.post(`${this.url}/${id}/reveal`, { log_action: logAction });
  }

  views() {
    return axios.get(`${this.url}/views`);
  }

  groupsUrl() {
    return this.url.replace(/credentials$/, 'credential_groups');
  }

  createGroup(payload) {
    return axios.post(this.groupsUrl(), { group: payload });
  }

  updateGroup(id, payload) {
    return axios.patch(`${this.groupsUrl()}/${id}`, { group: payload });
  }

  deleteGroup(id) {
    return axios.delete(`${this.groupsUrl()}/${id}`);
  }
}

export default new CredentialsAPI();
