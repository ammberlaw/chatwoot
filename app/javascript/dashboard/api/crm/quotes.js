/* global axios */
// 报价管理 API：CRUD + 汇总 + 客户带出 + 转销售订单 + 导出 xlsx。
// 明细以嵌套数组随报价整体提交（无每行图片，走普通 JSON，不用 multipart）。
const base = accountId => `/api/v1/accounts/${accountId}/crm/quotes`;

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
  // 新建/编辑走 multipart（明细含每行产品图 picture），payload 为 FormData。
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
  convertToSalesOrder(accountId, id) {
    return axios.post(`${base(accountId)}/${id}/convert_to_sales_order`);
  },
  // 在线预览：返回单据 + 模板里固定的抬头/条款文案（与导出同一份来源）。
  preview(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/preview`);
  },
  xlsx(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/xlsx`, { responseType: 'blob' });
  },
};
