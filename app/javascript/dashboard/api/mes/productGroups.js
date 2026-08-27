/* global axios */
import ApiClient from '../ApiClient';

// 产品分组树（不限层级）。读全员可见；维护限工程/PMC（后端 Mes::ProductGroupPolicy 再校验）。
class ProductGroupsAPI extends ApiClient {
  constructor() {
    super('mes/product_groups', { accountScoped: true });
  }

  createItem(payload) {
    return axios.post(this.url, { product_group: payload });
  }

  updateItem(id, payload) {
    return axios.patch(`${this.url}/${id}`, { product_group: payload });
  }

  deleteItem(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new ProductGroupsAPI();
