/* global axios */
import ApiClient from '../ApiClient';

class OaApprovalRequestAPI extends ApiClient {
  constructor() {
    super('oa/approval_requests', { accountScoped: true });
  }

  list(params = {}) {
    const query = new URLSearchParams(params).toString();
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

  counts() {
    return axios.get(`${this.url}/counts`);
  }

  submit(payload) {
    return axios.post(this.url, payload);
  }

  submitForm(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  approve(id, comment) {
    return axios.post(`${this.url}/${id}/approve`, { comment });
  }

  reject(id, comment) {
    return axios.post(`${this.url}/${id}/reject`, { comment });
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }
}

export default new OaApprovalRequestAPI();
