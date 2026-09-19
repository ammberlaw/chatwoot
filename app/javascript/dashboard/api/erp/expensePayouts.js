/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('expense_payouts');

// 审批通过但财务还没付钱的报销单（带金额、费用类型与建议科目）。
API.pending = () => axios.get(`${API.url}/pending`);
API.void = id => axios.post(`${API.url}/${id}/void`);

export default API;
