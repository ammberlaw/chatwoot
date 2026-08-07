/* global axios */
// 提成表 API：主单 + 明细嵌套（items_attributes）+ 审批流转 + xlsx 导出。
const base = accountId => `/api/v1/accounts/${accountId}/crm/commission_sheets`;

export default {
  list(accountId, params = {}) {
    return axios.get(base(accountId), { params });
  },
  get(accountId, id) {
    return axios.get(`${base(accountId)}/${id}`);
  },
  // 建本月提成表（已存在则后端直接返回该表）；自动带出当月订单。
  create(accountId, month, ownerId) {
    return axios.post(base(accountId), { month, owner_id: ownerId });
  },
  // 保存明细 + 备注。sheet = { remark, items_attributes: [...] }
  update(accountId, id, sheet) {
    return axios.patch(`${base(accountId)}/${id}`, { sheet });
  },
  remove(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
  pullOrders(accountId, id) {
    return axios.post(`${base(accountId)}/${id}/pull_orders`);
  },
  submit(accountId, id) {
    return axios.post(`${base(accountId)}/${id}/submit`);
  },
  approve(accountId, id) {
    return axios.post(`${base(accountId)}/${id}/approve`);
  },
  returnSheet(accountId, id, reason) {
    return axios.post(`${base(accountId)}/${id}/return_sheet`, { reason });
  },
  xlsx(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/xlsx`, { responseType: 'blob' });
  },
};
