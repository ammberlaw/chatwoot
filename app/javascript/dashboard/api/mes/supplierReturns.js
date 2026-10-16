/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('supplier_returns');

// 退出去（记日期）/ 登记返回（按行累加已返回数量）。
client.sendOut = (id, sentOn) =>
  axios.post(`${client.url}/${id}/send_out`, { sent_on: sentOn || undefined });
client.receiveBack = (id, rows, returnedOn) =>
  axios.post(`${client.url}/${id}/receive_back`, {
    rows,
    returned_on: returnedOn || undefined,
  });

export default client;
