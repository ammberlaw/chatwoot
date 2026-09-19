/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('stock_layers');

// 成品期初存货导入（财务从金蝶导出批次后一次性搬进来）。
API.import = file => {
  const form = new FormData();
  form.append('file', file);
  return axios.post(`${API.url}/import`, form);
};
API.importTemplate = () =>
  axios.get(`${API.url}/import_template`, { responseType: 'blob' });

export default API;
