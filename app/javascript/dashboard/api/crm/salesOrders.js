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

// 转单预览：订单明细逐行匹配产品档案（匹配在后端做，明细是自由文本、产品档案上千条）。
api.convertPreview = id => axios.get(`${api.url}/${id}/convert_preview`);

export default api;
