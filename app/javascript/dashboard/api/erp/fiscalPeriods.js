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
// 期末调汇：先预览差额，确认后生成待过账的调汇凭证。
API.revaluation = params => axios.get(`${API.url}/revaluation`, { params });
API.revalue = payload => axios.post(`${API.url}/revalue`, payload);
// 坏账计提（账龄分析法）：预览各段计提额，确认后生成计提/转回凭证。
API.badDebt = params => axios.get(`${API.url}/bad_debt`, { params });
API.provisionBadDebt = payload =>
  axios.post(`${API.url}/provision_bad_debt`, payload);

export default API;
