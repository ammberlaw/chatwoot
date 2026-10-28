/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('supplier_returns');

// 退出去（记日期）/ 登记返回（按行累加已返回数量）。
client.sendOut = (id, sentOn) =>
  axios.post(`${client.url}/${id}/send_out`, { sent_on: sentOn || undefined });
// warehouseId：换回来的货入哪个仓。换回来的是好货，默认进原料仓而不是回不良品仓。
client.receiveBack = (id, rows, returnedOn, warehouseId) =>
  axios.post(`${client.url}/${id}/receive_back`, {
    rows,
    returned_on: returnedOn || undefined,
    warehouse_id: warehouseId || undefined,
  });

export default client;
