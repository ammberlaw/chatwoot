/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// 组织架构资源通用客户端：index 支持任意查询参数（department_id…）。
export const buildOrgClient = resource => {
  class OrgResourceAPI extends ApiClient {
    constructor() {
      super(`org/${resource}`, { accountScoped: true });
    }

    get(params = {}) {
      const query = buildParams(params);
      return axios.get(query ? `${this.url}?${query}` : this.url);
    }
  }
  return new OrgResourceAPI();
};
