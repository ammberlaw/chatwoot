/* global axios */
// 生产订单上的物料反馈：采购更新供应商那边的情况（延误/改期/到货），业务只读。
// 挂在订单下面（嵌套资源），所以不走 buildMesClient 那套顶层 CRUD。
const base = accountId => `/api/v1/accounts/${accountId}/mes/production_orders`;

export default {
  get: (accountId, orderId) =>
    axios.get(`${base(accountId)}/${orderId}/order_feedbacks`),
  create: (accountId, orderId, payload) =>
    axios.post(`${base(accountId)}/${orderId}/order_feedbacks`, {
      order_feedback: payload,
    }),
  delete: (accountId, orderId, id) =>
    axios.delete(`${base(accountId)}/${orderId}/order_feedbacks/${id}`),
};
