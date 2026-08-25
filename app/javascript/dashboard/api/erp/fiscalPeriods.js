/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('fiscal_periods');

API.close = period => axios.post(`${API.url}/close`, { period });
API.reopen = period => axios.post(`${API.url}/reopen`, { period });

export default API;
