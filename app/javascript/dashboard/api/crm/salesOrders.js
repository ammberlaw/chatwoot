/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('sales_orders');

// 回收箱：已删订单列表 + 恢复（仅管理员/副管，后端 policy 兜底）。
api.deleted = () => axios.get(`${api.url}/deleted`);
api.restore = id => axios.post(`${api.url}/${id}/restore`);

export default api;
