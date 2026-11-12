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

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  updateForm(id, formData) {
    return axios.patch(`${this.url}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  approve(id, comment) {
    return axios.post(`${this.url}/${id}/approve`, { comment });
  }

  reject(id, comment) {
    return axios.post(`${this.url}/${id}/reject`, { comment });
  }

  submitDraftForm(id, data) {
    return axios.post(`${this.url}/${id}/submit_draft`, data);
  }

  resubmitForm(id, data) {
    return axios.post(`${this.url}/${id}/resubmit`, data);
  }

  events(id) {
    return axios.get(`${this.url}/${id}/events`);
  }

  remind(id) {
    return axios.post(`${this.url}/${id}/remind`);
  }

  transferCandidates(id) {
    return axios.get(`${this.url}/${id}/transfer_candidates`);
  }

  transfer(id, userId, reason) {
    return axios.post(`${this.url}/${id}/transfer`, {
      user_id: userId,
      reason,
    });
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  // 销假：对已通过的请假/外出单发起撤销。form_data 里带销假区间（键取原模板的日期字段）。
  // 返回的是一张新的审批单——销假本身要原审批人同意才生效。
  revoke(id, formData, submissionKey) {
    return axios.post(`${this.url}/${id}/revoke`, {
      form_data: formData,
      submission_key: submissionKey,
    });
  }
}

export default new OaApprovalRequestAPI();
