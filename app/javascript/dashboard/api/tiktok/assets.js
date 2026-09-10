/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// TK 固定资产登记。index 支持 department_id + status 过滤；带附件走 multipart。
class TiktokAssetsAPI extends ApiClient {
  constructor() {
    super('tiktok/assets', { accountScoped: true });
  }

  get(params = {}) {
    const query = buildParams(params);
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

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

export default new TiktokAssetsAPI();
