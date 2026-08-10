import ApiClient from '../ApiClient';

// TikTok 店铺主数据（录入下拉数据源）。CRUD 走 ApiClient 默认方法。
class TiktokShopsAPI extends ApiClient {
  constructor() {
    super('tiktok/shops', { accountScoped: true });
  }
}

export default new TiktokShopsAPI();
