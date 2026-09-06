/* global axios */
import { buildErpClient } from './_erpClient';

// 凭证模板：每月重复的分录存一份，新建凭证时一键带出。
const API = buildErpClient('voucher_templates');

API.remove = id => axios.delete(`${API.url}/${id}`);

export default API;
