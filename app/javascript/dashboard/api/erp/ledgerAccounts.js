/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('ledger_accounts');

// 一键初始化/补齐国标标准科目表（后端幂等，不覆盖已有科目）。
API.initializeStandard = () => axios.post(`${API.url}/initialize_standard`);

// 存货科目映射：产品档案「来源类别」→ 存货科目（采购入库凭证的借方科目）。
API.inventoryMap = () => axios.get(`${API.url}/inventory_map`);
API.updateInventoryMap = map =>
  axios.put(`${API.url}/update_inventory_map`, { map });

export default API;
