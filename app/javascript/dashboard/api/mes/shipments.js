/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('shipments');

// 通知出库 / 出库过账。
client.notify = id => axios.post(`${client.url}/${id}/notify`);
client.ship = id => axios.post(`${client.url}/${id}/ship`);

// 「我为什么干不了这件事」只读诊断（见 Mes::ShipmentDiagnosis）。
// do_action 而不是 action：action 是 Rails 路由保留参数名，传了会被吞掉。
client.diagnose = (id, doAction) =>
  axios.get(`${client.url}/${id}/diagnose`, {
    params: { do_action: doAction },
  });

// 现货出库审核链：重新提交 / 主管通过 / 主管驳回 / 待我审核收件箱。
client.submit = id => axios.post(`${client.url}/${id}/submit`);
// 审核通过：款没收齐时财务可放行，但要带 note（理由）——后端校验并留痕。
client.approve = (id, note) =>
  axios.post(`${client.url}/${id}/approve`, { note });
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });
client.approvalInbox = () => axios.get(`${client.url}/approval_inbox`);

// 做错了要重来：退回草稿就地改 / 整张作废（作废要填原因）。
client.revertToDraft = id => axios.post(`${client.url}/${id}/revert_to_draft`);
client.void = (id, reason) =>
  axios.post(`${client.url}/${id}/void`, { reason });

// 批量打印后记一次打印次数（仓库每月整叠打给财务核对，要分出打过没打过）。
client.markPrinted = ids => axios.post(`${client.url}/mark_printed`, { ids });

// 销售订单一键转现货出库单（库存单轨道）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

export default client;
