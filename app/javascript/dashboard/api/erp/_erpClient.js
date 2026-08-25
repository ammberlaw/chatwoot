/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// ERP（财务）资源通用客户端：index 支持任意查询参数（q/active/period…）。与 MES 客户端同构。
export const buildErpClient = resource => {
  class ErpResourceAPI extends ApiClient {
    constructor() {
      super(`erp/${resource}`, { accountScoped: true });
    }

    get(params = {}) {
      const query = buildParams(params);
      return axios.get(query ? `${this.url}?${query}` : this.url);
    }
  }
  return new ErpResourceAPI();
};
