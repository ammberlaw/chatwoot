/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// TikTok 每日销售录入。index 支持 month(YYYY-MM) + shop_id 过滤。
class TiktokSalesRecordsAPI extends ApiClient {
  constructor() {
    super('tiktok/sales_records', { accountScoped: true });
  }

  get(params = {}) {
    const query = buildParams(params);
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }
}

export default new TiktokSalesRecordsAPI();
