/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('payment_records');

API.createWithAllocations = payload => axios.post(API.url, payload);
API.updateWithAllocations = (id, payload) =>
  axios.patch(`${API.url}/${id}`, payload);
API.void = id => axios.post(`${API.url}/${id}/void`);

export default API;
