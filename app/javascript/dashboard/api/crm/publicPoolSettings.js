/* global axios */
import ApiClient from '../ApiClient';

class PublicPoolSettingsAPI extends ApiClient {
  constructor() {
    super('crm/public_pool_settings', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateSetting(payload) {
    return axios.patch(this.url, payload);
  }
}

export default new PublicPoolSettingsAPI();
