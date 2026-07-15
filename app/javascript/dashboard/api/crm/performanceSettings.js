/* global axios */
import ApiClient from '../ApiClient';

class PerformanceSettingsAPI extends ApiClient {
  constructor() {
    super('crm/performance_settings', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateSetting(payload) {
    return axios.patch(this.url, payload);
  }
}

export default new PerformanceSettingsAPI();
