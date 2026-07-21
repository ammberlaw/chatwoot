/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('shipments');

// 通知出库 / 出库过账。
client.notify = id => axios.post(`${client.url}/${id}/notify`);
client.ship = id => axios.post(`${client.url}/${id}/ship`);

export default client;
