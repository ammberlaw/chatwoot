/* global axios */
import ApiClient from '../ApiClient';

// 账套级财务政策（单例资源：erp/settings，无 id）。
class ErpSettingsAPI extends ApiClient {
  constructor() {
    super('erp/settings', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  save(setting) {
    return axios.patch(this.url, { setting });
  }
}

export default new ErpSettingsAPI();
