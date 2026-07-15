/* global axios */
import ApiClient from '../ApiClient';

class DocSectionsAPI extends ApiClient {
  constructor() {
    super('crm/doc_sections', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  createSection(payload) {
    return axios.post(this.url, payload);
  }

  updateSection(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  deleteSection(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new DocSectionsAPI();
