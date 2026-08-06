/* global axios */
import ApiClient from '../ApiClient';

// CRM 客户设置：客户分组 / 客户来源 自定义项（二级层级）。写操作仅管理员/副管理员。
class OptionItemsAPI extends ApiClient {
  constructor() {
    super('crm/option_items', { accountScoped: true });
  }

  get(category) {
    return axios.get(`${this.url}?category=${encodeURIComponent(category)}`);
  }

  createItem(payload) {
    return axios.post(this.url, { option_item: payload });
  }

  updateItem(id, payload) {
    return axios.patch(`${this.url}/${id}`, { option_item: payload });
  }

  deleteItem(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new OptionItemsAPI();
