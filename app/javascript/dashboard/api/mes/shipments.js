/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('shipments');

// 通知出库 / 出库过账。
client.notify = id => axios.post(`${client.url}/${id}/notify`);
client.ship = id => axios.post(`${client.url}/${id}/ship`);

// 现货出库审核链：重新提交 / 主管通过 / 主管驳回 / 待我审核收件箱。
client.submit = id => axios.post(`${client.url}/${id}/submit`);
// 审核通过：款没收齐时财务可放行，但要带 note（理由）——后端校验并留痕。
client.approve = (id, note) =>
  axios.post(`${client.url}/${id}/approve`, { note });
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

// 销售订单一键转现货出库单（库存单轨道）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

export default client;
