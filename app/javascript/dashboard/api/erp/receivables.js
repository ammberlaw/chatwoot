/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('receivables');

// 收款单核销时的候选：该客户未收清的台账。
API.openList = params => axios.get(`${API.url}/open_list`, { params });
API.aging = params => axios.get(`${API.url}/aging`, { params });

// 待建账：已确认但还没建应收的销售订单 + 批量补建。
API.pendingOrders = params => axios.get(`${API.url}/pending_orders`, { params });
API.bulkBuild = ids =>
  axios.post(`${API.url}/bulk_build`, { crm_sales_order_ids: ids });

export default API;
