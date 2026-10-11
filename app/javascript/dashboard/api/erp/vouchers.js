/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('vouchers');

// 状态流转（后端 Erp::VoucherPostingService 兜硬规则）：过账 / 红冲 / 作废。
API.postVoucher = id => axios.post(`${API.url}/${id}/post_voucher`);
API.reverse = id => axios.post(`${API.url}/${id}/reverse`);
// 批量过账：一次把选中的待过账凭证全过了（后端逐张校验，不平的单独回报，不拖垮整批）。
API.bulkPost = voucherIds =>
  axios.post(`${API.url}/bulk_post`, { voucher_ids: voucherIds });
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

// 录入效率三件套：常用摘要联想 / 凭证模板 / CSV 批量导入。
API.summaries = q => axios.get(`${API.url}/summaries`, { params: { q } });
API.import = file => {
  const form = new FormData();
  form.append('file', file);
  return axios.post(`${API.url}/import`, form);
};
API.importTemplate = () =>
  axios.get(`${API.url}/import_template`, { responseType: 'blob' });

export default API;
