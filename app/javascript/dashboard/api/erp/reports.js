/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  ).toString();

// 财务报表：资产负债表（时点）/ 利润表 / 现金流量表（期间），只读实时算。
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

  cashFlow(params = {}) {
    return axios.get(`${this.url}/cash_flow?${buildParams(params)}`);
  }

  cashFlowItems() {
    return axios.get(`${this.url}/cash_flow_items`);
  }

  // 审计接口：区间内已记账数据打包 zip（科目表/序时簿/余额表/国标 XML）。
  auditExport(params = {}) {
    return axios.get(`${this.url}/audit_export?${buildParams(params)}`, {
      responseType: 'blob',
    });
  }
}

export default new ErpReportAPI();
