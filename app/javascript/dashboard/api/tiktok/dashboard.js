/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// TikTok 数据看板：按 month(YYYY-MM) + shop_id 拉汇总。
class TiktokDashboardAPI extends ApiClient {
  constructor() {
    super('tiktok/dashboard', { accountScoped: true });
  }

  show(params = {}) {
    const query = buildParams(params);
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }
}

export default new TiktokDashboardAPI();
