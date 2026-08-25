/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('receipt_records');

// 收款单带核销行一起提交（后端 AllocationService 整单覆盖式重设）。
API.createWithAllocations = payload => axios.post(API.url, payload);
API.updateWithAllocations = (id, payload) =>
  axios.patch(`${API.url}/${id}`, payload);
API.void = id => axios.post(`${API.url}/${id}/void`);

export default API;
