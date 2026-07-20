/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('production_orders');

// 从销售订单一键转生产订单（脊柱起点）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

// 挂工程 BOM → 进 BOM_READY。
client.attachBom = (id, payload) =>
  axios.post(`${client.url}/${id}/attach_bom`, payload);

export default client;
