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
}

export default new OaApprovalTemplateAPI();
