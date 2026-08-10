import ApiClient from '../ApiClient';

// TikTok 今日速览：当天各店售出数据 + 汇总。GET tiktok/today。
class TiktokTodayAPI extends ApiClient {
  constructor() {
    super('tiktok/today', { accountScoped: true });
  }
}

export default new TiktokTodayAPI();
