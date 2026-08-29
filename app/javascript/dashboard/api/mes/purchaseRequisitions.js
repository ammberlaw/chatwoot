/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('purchase_requisitions');

// 提交（DRAFT → OPEN，无审批，采购即可见）/ 作废。
client.submit = id => axios.post(`${client.url}/${id}/submit`);
client.cancel = id => axios.post(`${client.url}/${id}/cancel`);

// 转采购单（拆批 + 改量）：lines=[{ requisition_item_id, qty, mes_supplier_id? }] + 采购单头字段。
client.convert = (id, payload) =>
  axios.post(`${client.url}/${id}/convert`, payload);

export default client;
