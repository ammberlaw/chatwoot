/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('fixed_assets');

// 一键计提本期折旧（汇总成一张待过账凭证）与处置/报废。
API.depreciate = period => axios.post(`${API.url}/depreciate`, { period });
API.dispose = (id, payload) => axios.post(`${API.url}/${id}/dispose`, payload);

// Excel 批量导入（期初建账用，连「已提折旧」一起搬）+ 模板下载。
API.import = file => {
  const form = new FormData();
  form.append('file', file);
  return axios.post(`${API.url}/import`, form);
};
API.importTemplate = () =>
  axios.get(`${API.url}/import_template`, { responseType: 'blob' });

export default API;
