/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('shipments');

// 通知出库 / 出库过账。
client.notify = id => axios.post(`${client.url}/${id}/notify`);
client.ship = id => axios.post(`${client.url}/${id}/ship`);

// 现货出库审核链：重新提交 / 主管通过 / 主管驳回 / 待我审核收件箱。
client.submit = id => axios.post(`${client.url}/${id}/submit`);
client.approve = id => axios.post(`${client.url}/${id}/approve`);
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

export default client;
