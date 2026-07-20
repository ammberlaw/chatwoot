/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('purchase_orders');

// BOM 算料：按生产订单展开采购需求，供采购单预填。
client.requirement = productionOrderId =>
  axios.get(`${client.url}/requirement`, {
    params: { production_order_id: productionOrderId },
  });

export default client;
