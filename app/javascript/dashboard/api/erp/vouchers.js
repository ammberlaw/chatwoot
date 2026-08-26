/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('vouchers');

// 状态流转（后端 Erp::VoucherPostingService 兜硬规则）：过账 / 红冲 / 作废。
API.postVoucher = id => axios.post(`${API.url}/${id}/post_voucher`);
API.reverse = id => axios.post(`${API.url}/${id}/reverse`);
API.void = id => axios.post(`${API.url}/${id}/void`);

// 原始单据影像（发票 / 水单扫描件）。已过账凭证也允许补传。
API.attach = (id, files) => {
  const form = new FormData();
  files.forEach(file => form.append('files[]', file));
  return axios.post(`${API.url}/${id}/attach`, form);
};
API.detach = (id, attachmentId) =>
  axios.delete(`${API.url}/${id}/detach`, {
    params: { attachment_id: attachmentId },
  });

export default API;
