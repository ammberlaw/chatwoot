/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('auto_voucher_rules');

API.toggle = (id, isActive) =>
  axios.patch(`${API.url}/${id}`, { rule: { is_active: isActive } });

export default API;
