/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('sales_orders');

// 回收箱：已删订单列表 + 恢复（仅管理员/副管，后端 policy 兜底）。
api.deleted = () => axios.get(`${api.url}/deleted`);
api.restore = id => axios.post(`${api.url}/${id}/restore`);

// PI 文件识别（上传 multipart，返回字段化结果）。历史 PI 批量补录逐个调它。
api.parsePi = formData =>
  axios.post(`${api.url}/parse_pi`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default api;
