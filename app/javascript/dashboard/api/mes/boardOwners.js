/* global axios */
import ApiClient from '../ApiClient';

// MES 阶段板块负责人：index 全员可读，set 由管理员按 board_key 配置。
class MesBoardOwnersAPI extends ApiClient {
  constructor() {
    super('mes/board_owners', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  set(payload) {
    return axios.put(`${this.url}/set`, payload);
  }
}

export default new MesBoardOwnersAPI();
