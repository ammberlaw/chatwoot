/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('auto_voucher_rules');

API.toggle = (id, isActive) =>
  axios.patch(`${API.url}/${id}`, { rule: { is_active: isActive } });

// 科目映射：整份 config 覆盖（后端 permit config: {}）。
API.saveConfig = (id, config) =>
  axios.patch(`${API.url}/${id}`, { rule: { config } });

export default API;
