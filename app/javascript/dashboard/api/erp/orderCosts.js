/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('order_costs');

// 毛利报表：订单维度 + 可选按业务员/客户汇总。
API.margin = params => axios.get(`${API.url}/margin`, { params });

export default API;
