/* global axios */
import ApiClient from '../ApiClient';

// 定制报价申请：业务员按产品线模板填参数，主管(或被转交的人)填价格回来。
class QuoteRequestsAPI extends ApiClient {
  constructor() {
    super('crm/quote_requests', { accountScoped: true });
  }

  // 业务员填表用的模板（只含启用的）
  templates() {
    return axios.get(`${this.url}/templates`);
  }

  submit(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // 撤销后重新编辑再交（多部件：可能补了附件）。
  resubmit(id, formData) {
    return axios.put(`${this.url}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  quote(id, payload) {
    return axios.post(`${this.url}/${id}/quote`, payload);
  }

  transfer(id, toUserId, reason) {
    return axios.post(`${this.url}/${id}/transfer`, {
      to_user_id: toUserId,
      reason,
    });
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }
}

export default new QuoteRequestsAPI();
