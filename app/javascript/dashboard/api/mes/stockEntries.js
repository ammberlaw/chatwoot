/* global axios */
import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

const client = withReturnActions(buildMesClient('stock_entries'));

// 批量打印后记一次打印次数（仓库每月整叠打给财务核对，要分出打过没打过）。
client.markPrinted = ids =>
  axios.post(`${client.url}/mark_printed`, { ids });

// 过账：刷结存 + 记流水 + 阶段推进。
client.post = id => axios.post(`${client.url}/${id}/post`);

// 作废（冲销）：反向冲回已过账库存 + 按需回退生产订单阶段，置「已作废」保留可追溯。
client.cancel = id => axios.post(`${client.url}/${id}/cancel`);

// 成品入库：仓库清点确认（确认即过账入库）。
client.confirmWarehouse = id =>
  axios.post(`${client.url}/${id}/confirm_warehouse`);

// 财务审核：通过 / 驳回（驳回必须填原因）。审核通过才能过账。
client.approve = id => axios.post(`${client.url}/${id}/approve`);
client.reject = (id, reason) =>
  axios.post(`${client.url}/${id}/reject`, { reason });

// 原料↔成品转换：建单即过账，一张单两行（见 Mes::StockConvertService）。
client.convert = payload => axios.post(`${client.url}/convert`, payload);

// 收货单文件暂存为 blob，返回 signed_id（原料入库必传）。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default client;
