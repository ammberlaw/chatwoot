/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// 财务报表：资产负债表（时点）/ 利润表（期间），只读实时算。
class ErpReportAPI extends ApiClient {
  constructor() {
    super('erp/reports', { accountScoped: true });
  }

  balanceSheet(params = {}) {
    return axios.get(`${this.url}/balance_sheet?${buildParams(params)}`);
  }

  incomeStatement(params = {}) {
    return axios.get(`${this.url}/income_statement?${buildParams(params)}`);
  }
}

export default new ErpReportAPI();
