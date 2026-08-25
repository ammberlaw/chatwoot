/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('payables');

API.openList = params => axios.get(`${API.url}/open_list`, { params });
API.supplierStatement = () => axios.get(`${API.url}/supplier_statement`);
API.buildFromPurchaseOrder = purchaseOrderId =>
  axios.post(API.url, { mes_purchase_order_id: purchaseOrderId });

export default API;
