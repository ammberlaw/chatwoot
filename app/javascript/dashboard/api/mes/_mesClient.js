/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// MES 资源通用客户端：index 支持任意查询参数（filter/stage/status/q…）。
export const buildMesClient = resource => {
  class MesResourceAPI extends ApiClient {
    constructor() {
      super(`mes/${resource}`, { accountScoped: true });
    }

    get(params = {}) {
      const query = buildParams(params);
      return axios.get(query ? `${this.url}?${query}` : this.url);
    }

    createWithFiles(formData) {
      return axios.post(this.url, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }
  }
  return new MesResourceAPI();
};
