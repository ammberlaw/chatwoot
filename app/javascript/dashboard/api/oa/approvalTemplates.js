/* global axios */
import ApiClient from '../ApiClient';

class OaApprovalTemplateAPI extends ApiClient {
  constructor() {
    super('oa/approval_templates', { accountScoped: true });
  }

  get(params = {}) {
    const query = new URLSearchParams(params).toString();
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

  save(fields) {
    return axios.post(this.url, { template: fields });
  }

  modify(id, fields) {
    return axios.patch(`${this.url}/${id}`, { template: fields });
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new OaApprovalTemplateAPI();
