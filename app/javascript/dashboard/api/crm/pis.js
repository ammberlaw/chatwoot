/* global axios */
// PI（形式发票）API：新建/编辑走 multipart（含明细嵌套 + 每行商品图），故不套通用 crmClient。
const base = accountId => `/api/v1/accounts/${accountId}/crm/pis`;

export default {
  list(accountId, params = {}) {
    return axios.get(base(accountId), { params });
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
  xlsx(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/xlsx`, { responseType: 'blob' });
  },
};
