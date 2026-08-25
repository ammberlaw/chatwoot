/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('vouchers');

// 状态流转（后端 Erp::VoucherPostingService 兜硬规则）：过账 / 红冲 / 作废。
API.postVoucher = id => axios.post(`${API.url}/${id}/post_voucher`);
API.reverse = id => axios.post(`${API.url}/${id}/reverse`);
API.void = id => axios.post(`${API.url}/${id}/void`);

export default API;
