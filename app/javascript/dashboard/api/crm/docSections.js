/* global axios */
import ApiClient from '../ApiClient';

class DocSectionsAPI extends ApiClient {
  constructor() {
    super('crm/doc_sections', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateSection(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }
}

export default new DocSectionsAPI();
