/* global axios */
import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

const client = withReturnActions(buildMesClient('purchase_orders'));

// BOM 算料：按生产订单展开采购需求，供采购单预填。
// category 可选：MACHINE 主料(整机料) / PACKAGING 辅料(包装料)——两个采购员分料建单。
client.requirement = (productionOrderId, category = '') =>
  axios.get(`${client.url}/requirement`, {
    params: {
      production_order_id: productionOrderId,
      category: category || undefined,
    },
  });

export default client;
