/* global axios */
import ApiClient from '../ApiClient';

// PI 卖方预录（单例，按人隔离）：读/存当前业务员的对外落款联系方式（联系人/手机/邮箱）。
class PiSellerProfileAPI extends ApiClient {
  constructor() {
    super('crm/pi_seller_profile', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(payload) {
    return axios.patch(this.url, { pi_seller_profile: payload });
  }
}

export default new PiSellerProfileAPI();
