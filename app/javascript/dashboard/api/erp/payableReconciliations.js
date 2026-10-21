/* global axios */
import { buildErpClient } from './_erpClient';

// 应付「先对账再建账」：收了货先跟供应商核对，对好了才落台账。
const API = buildErpClient('payable_reconciliations');

API.confirm = (purchaseOrderId, supplierId) =>
  axios.post(`${API.url}/confirm`, {
    mes_purchase_order_id: purchaseOrderId,
    mes_supplier_id: supplierId,
  });

export default API;
