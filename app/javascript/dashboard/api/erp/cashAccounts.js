/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('cash_accounts');

// 出纳日记账（只增不改的资金流水）与内部划转。
API.transactions = params => axios.get(`${API.url}/transactions`, { params });
API.transfer = payload => axios.post(`${API.url}/transfer`, payload);

export default API;
