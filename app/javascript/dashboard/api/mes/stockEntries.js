/* global axios */
import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

const client = withReturnActions(buildMesClient('stock_entries'));

// 过账：刷结存 + 记流水 + 阶段推进。
client.post = id => axios.post(`${client.url}/${id}/post`);

// 作废（冲销）：反向冲回已过账库存 + 按需回退生产订单阶段，置「已作废」保留可追溯。
client.cancel = id => axios.post(`${client.url}/${id}/cancel`);

// 成品入库：仓库清点确认（确认即过账入库）。
client.confirmWarehouse = id =>
  axios.post(`${client.url}/${id}/confirm_warehouse`);

// 收货单文件暂存为 blob，返回 signed_id（原料入库必传）。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default client;
