/* global axios */
import ApiClient from '../ApiClient';

// 财务看板：单例资源，只读。
class ErpDashboardAPI extends ApiClient {
  constructor() {
    super('erp/dashboard', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }
}

export default new ErpDashboardAPI();
