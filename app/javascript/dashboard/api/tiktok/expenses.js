/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// TK 支出台账。index 支持 month(YYYY-MM) + department_id + shop_id 过滤。
class TiktokExpensesAPI extends ApiClient {
  constructor() {
    super('tiktok/expenses', { accountScoped: true });
  }

  get(params = {}) {
    const query = buildParams(params);
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

  // 带票据走 multipart（后端 attach 追加，不动已有附件）。
  createWithFiles(formData) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateWithFiles(id, formData) {
    return axios.patch(`${this.url}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new TiktokExpensesAPI();
