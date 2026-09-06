/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('fixed_assets');

// 一键计提本期折旧（汇总成一张待过账凭证）与处置/报废。
API.depreciate = period => axios.post(`${API.url}/depreciate`, { period });
API.dispose = (id, payload) => axios.post(`${API.url}/${id}/dispose`, payload);

export default API;
