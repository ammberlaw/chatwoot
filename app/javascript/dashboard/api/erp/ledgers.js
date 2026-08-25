/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// 账簿：只读实时查询（余额表 / 明细账 / 维度明细账），无增删改故不走通用 ERP 客户端。
class ErpLedgerAPI extends ApiClient {
  constructor() {
    super('erp/ledgers', { accountScoped: true });
  }

  balances(params = {}) {
    return axios.get(`${this.url}/balances?${buildParams(params)}`);
  }

  entries(params = {}) {
    return axios.get(`${this.url}/entries?${buildParams(params)}`);
  }

  dimensions(params = {}) {
    return axios.get(`${this.url}/dimensions?${buildParams(params)}`);
  }
}

export default new ErpLedgerAPI();
