/* global axios */
// PI（形式发票）API：新建/编辑走 multipart（含明细嵌套 + 每行商品图），故不套通用 crmClient。
const base = accountId => `/api/v1/accounts/${accountId}/crm/pis`;

export default {
  list(accountId, params = {}) {
    return axios.get(base(accountId), { params });
  },
  summary(accountId, params = {}) {
    return axios.get(`${base(accountId)}/summary`, { params });
  },
  get(accountId, id) {
    return axios.get(`${base(accountId)}/${id}`);
  },
  create(accountId, formData) {
    return axios.post(base(accountId), formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  update(accountId, id, formData) {
    return axios.patch(`${base(accountId)}/${id}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
  remove(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
  prefill(accountId, customerId) {
    return axios.get(`${base(accountId)}/prefill`, {
      params: { customer_id: customerId },
    });
  },
  // 在线预览：返回单据 + 已解析的公司抬头/银行块（与导出同一份常量）。
  preview(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/preview`);
  },
  xlsx(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/xlsx`, { responseType: 'blob' });
  },
  companyHeaders(accountId) {
    return axios.get(`${base(accountId)}/company_headers`);
  },
  parsePi(accountId, formData) {
    return axios.post(`${base(accountId)}/parse_pi`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  },
};
