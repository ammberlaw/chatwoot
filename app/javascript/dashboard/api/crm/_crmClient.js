/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// CRM 资源通用客户端：index 支持任意查询参数（filter/status/folder/customer_id…）
export const buildCrmClient = resource => {
  class CrmResourceAPI extends ApiClient {
    constructor() {
      super(`crm/${resource}`, { accountScoped: true });
    }

    get(params = {}) {
      const query = buildParams(params);
      return axios.get(query ? `${this.url}?${query}` : this.url);
    }
  }
  return new CrmResourceAPI();
};
