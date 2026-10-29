/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('cash_accounts');

// 出纳日记账（只增不改的资金流水）与内部划转。
API.transactions = params => axios.get(`${API.url}/transactions`, { params });
API.transfer = payload => axios.post(`${API.url}/transfer`, payload);
// 资金报表：一个期间里各账户的期初/收/支/期末 + 折 CNY 合计。
API.report = params => axios.get(`${API.url}/report`, { params });

// 银行日记账 Excel 导入（账户按名称匹配资金账户，重复导入按账户+日期+摘要+金额判重）。
API.importTransactions = formData =>
  axios.post(`${API.url}/import_transactions`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default API;
