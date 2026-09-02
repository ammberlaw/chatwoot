/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('order_costs');

// 毛利报表：订单维度 + 可选按业务员/客户汇总。
API.margin = params => axios.get(`${API.url}/margin`, { params });

// 一键归集 MES 的领料/外协采购为成本行（补历史；日常出货时自动触发）。幂等，重复点不翻倍。
API.rollup = params => axios.post(`${API.url}/rollup`, params);

export default API;
