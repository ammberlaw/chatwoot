/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('production_orders');

// 从销售订单一键转生产订单（脊柱起点）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

// 挂工程 BOM → 进 BOM_READY。
client.attachBom = (id, payload) =>
  axios.post(`${client.url}/${id}/attach_bom`, payload);

// 下发到采购阶段（BOM_READY → PURCHASING）。
client.releasePurchasing = id =>
  axios.post(`${client.url}/${id}/release_purchasing`);

// 按 BOM 推料需求（生产领料预填）。
client.requirement = id => axios.get(`${client.url}/${id}/requirement`);

// 接单 / 拒收打回（P1 接单确认）。
client.acknowledge = id => axios.post(`${client.url}/${id}/acknowledge`);
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });

// 我的待办：停在我负责阶段的在产订单。
client.inbox = () => axios.get(`${client.url}/inbox`);

export default client;
