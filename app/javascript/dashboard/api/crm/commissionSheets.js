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
  // 选单导入：列出可选销售订单 / 导入选中的订单。
  selectableOrders(accountId, id) {
    return axios.get(`${base(accountId)}/${id}/selectable_orders`);
  },
  importOrders(accountId, id, orderIds, productCategory) {
    return axios.post(`${base(accountId)}/${id}/import_orders`, {
      order_ids: orderIds,
      product_category: productCategory,
    });
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
  // 财务发放：批量标记「已通过」提成表为已发放，逐张带实发金额/备注。
  // items = [{ id, paid_amount_micros, paid_note }]；单张亦走此接口。
  markPaid(accountId, items) {
    return axios.post(`${base(accountId)}/mark_paid`, { items });
  },
  unmarkPaid(accountId, ids) {
    return axios.post(`${base(accountId)}/unmark_paid`, { ids });
  },
  // 提成点配置（品类→点位%）：列出 / 批量保存。
  rates(accountId) {
    return axios.get(`${base(accountId)}/rates`);
  },
  saveRates(accountId, rows) {
    return axios.post(`${base(accountId)}/save_rates`, { rates: rows });
  },
};
