/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('receivables');

// 收款单核销时的候选：该客户未收清的台账。
API.openList = params => axios.get(`${API.url}/open_list`, { params });

export default API;
