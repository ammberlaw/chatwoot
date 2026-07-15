/* global axios */
import ApiClient from '../ApiClient';

class DocCenterSettingsAPI extends ApiClient {
  constructor() {
    super('crm/doc_center_settings', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateSetting(payload) {
    return axios.patch(this.url, payload);
  }
}

export default new DocCenterSettingsAPI();
