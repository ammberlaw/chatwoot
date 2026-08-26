/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('fiscal_periods');

API.close = period => axios.post(`${API.url}/close`, { period });
API.reopen = period => axios.post(`${API.url}/reopen`, { period });
// 期初建账（整张替换式保存）与两账对平（台账 vs 总账）。
API.openingBalance = () => axios.get(`${API.url}/opening_balance`);
API.saveOpeningBalance = payload =>
  axios.post(`${API.url}/save_opening_balance`, payload);
API.reconciliation = params =>
  axios.get(`${API.url}/reconciliation`, { params });

export default API;
