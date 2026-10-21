/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('payables');

API.openList = params => axios.get(`${API.url}/open_list`, { params });
API.supplierStatement = () => axios.get(`${API.url}/supplier_statement`);
API.buildFromPurchaseOrder = purchaseOrderId =>
  axios.post(API.url, { mes_purchase_order_id: purchaseOrderId });
API.aging = params => axios.get(`${API.url}/aging`, { params });
API.monthly = params => axios.get(`${API.url}/monthly`, { params });
// 台账明细弹窗：这笔应付是哪张采购单、哪几行料、货到没到、付了几次。
API.detail = id => axios.get(`${API.url}/${id}/detail`);

// 该出没出应付凭证的入库单（应付凭证是原料入库过账时出的，不在台账上生成）。
API.pendingVouchers = () => axios.get(`${API.url}/pending_vouchers`);
API.buildReceiptVoucher = stockEntryId =>
  axios.post(`${API.url}/build_receipt_voucher`, {
    stock_entry_id: stockEntryId,
  });

export default API;
