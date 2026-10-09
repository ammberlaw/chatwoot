/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// TikTok 出库利润表。index / export 支持 month(YYYY-MM) + shop_id + department_id 过滤。
class TiktokProfitRecordsAPI extends ApiClient {
  constructor() {
    super('tiktok/profit_records', { accountScoped: true });
  }

  get(params = {}) {
    const query = buildParams(params);
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

  // 报表导出（.xlsx）：筛选条件与列表一致，导的是全部符合条件的记录。
  export(params = {}) {
    const query = buildParams(params);
    return axios.get(`${this.url}/export${query ? `?${query}` : ''}`, {
      responseType: 'blob',
    });
  }
}

export default new TiktokProfitRecordsAPI();
