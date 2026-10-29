/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('bom_costs');

// Excel 批量导入（商品编码 / 产品名称 / 规格型号 / 加工费 / 制造费用）。
// 只认商品编码；对不上产品档案的行整行退回，不自动建档。
API.import = formData =>
  axios.post(`${API.url}/import`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// 展开看这个成品编码下的物料明细与料价（点开那一行才拉，不在列表里一次性带）。
API.materials = id => axios.get(`${API.url}/${id}/materials`);

// 制造费用按月分摊：preview 只算不写（给财务先看分子分母），allocate 才落账。
API.overheadPreview = period =>
  axios.get(`${API.url}/overhead_preview`, { params: { period } });

API.overheadAllocate = period =>
  axios.post(`${API.url}/overhead_allocate`, { period });

export default API;
