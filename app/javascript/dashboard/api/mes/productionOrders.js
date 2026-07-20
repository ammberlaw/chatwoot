/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('production_orders');

// 从销售订单一键转生产订单（脊柱起点）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

export default client;
