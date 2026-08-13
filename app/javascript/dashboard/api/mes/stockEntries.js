/* global axios */
import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

const client = withReturnActions(buildMesClient('stock_entries'));

// 过账：刷结存 + 记流水 + 阶段推进。
client.post = id => axios.post(`${client.url}/${id}/post`);

// 成品入库：仓库清点确认（确认即过账入库）。
client.confirmWarehouse = id =>
  axios.post(`${client.url}/${id}/confirm_warehouse`);

export default client;
