/* global axios */
import { buildMesClient } from './_mesClient';

// 委外加工单：主单 + 它派生的三张库存单（发料 / 产品入库 / 退料）。
const client = buildMesClient('outsource_orders');

// 建单只能从生产订单转（后端 Mes::OutsourceOrderBuilder），所以 create 另走一条。
client.createFromProductionOrder = (productionOrderId, attrs) =>
  axios.post(client.url, {
    production_order_id: productionOrderId,
    outsource_order: attrs,
  });

client.confirm = id => axios.post(`${client.url}/${id}/confirm`);
client.close = id => axios.post(`${client.url}/${id}/close`);

// rows 不传＝按「还没发的标准用量」整单带出；传了就按传的发（分批发料）。
client.issue = (id, rows) =>
  axios.post(`${client.url}/${id}/issue`, { rows: rows || undefined });

// 产品入库：qty=这次实收多少台，后端按它倒冲委外仓的料。
client.receipt = (id, qty, toWarehouseId) =>
  axios.post(`${client.url}/${id}/receipt`, {
    qty,
    to_warehouse_id: toWarehouseId || undefined,
  });

client.returnMaterials = (id, rows, toWarehouseId) =>
  axios.post(`${client.url}/${id}/return_materials`, {
    rows,
    to_warehouse_id: toWarehouseId,
  });

// 生成加工费应付。手动动作：财务跟加工厂对完账再点。
client.generateFee = id => axios.post(`${client.url}/${id}/generate_fee`);

export default client;
