/* global axios */
import ApiClient from '../ApiClient';

// 产品辅助属性：挂在某个产品下面的可选变体（喷码6000 / 喷码3500…）。
// 路径是 /mes/products/:productId/aux_attributes，所以不套 buildMesClient。
class ProductAuxAttributesAPI extends ApiClient {
  constructor() {
    super('mes/products', { accountScoped: true });
  }

  base(productId) {
    return `${this.url}/${productId}/aux_attributes`;
  }

  list(productId) {
    return axios.get(this.base(productId));
  }

  add(productId, payload) {
    return axios.post(this.base(productId), { aux_attribute: payload });
  }

  edit(productId, id, payload) {
    return axios.patch(`${this.base(productId)}/${id}`, {
      aux_attribute: payload,
    });
  }

  // 被单据选过的只会停用（返回 deactivated: true），没被选过的才真删。
  remove(productId, id) {
    return axios.delete(`${this.base(productId)}/${id}`);
  }
}

export default new ProductAuxAttributesAPI();
