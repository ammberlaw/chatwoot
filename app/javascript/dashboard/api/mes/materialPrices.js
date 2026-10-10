/* global axios */
import { buildMesClient } from './_mesClient';

const API = buildMesClient('material_prices');

// Excel 批量导入（物料编码 / 单价）。只认物料编码；对不上商品档的行整行退回。
API.import = formData =>
  axios.post(`${API.url}/import`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// 缺价清单：生产任务单用到、但三级价源都查不到价的物料，按被用到的单数倒序。
API.missing = () => axios.get(`${API.url}/missing`);

export default API;
