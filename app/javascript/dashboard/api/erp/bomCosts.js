/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('bom_costs');

// Excel 批量导入（商品编码 / 产品名称 / 规格型号 / 加工费 / 制造费用）。
// 只认商品编码；对不上产品档案的行整行退回，不自动建档。
API.import = formData =>
  axios.post(`${API.url}/import`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default API;
