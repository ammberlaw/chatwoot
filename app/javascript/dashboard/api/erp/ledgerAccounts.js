/* global axios */
import { buildErpClient } from './_erpClient';

const API = buildErpClient('ledger_accounts');

// 一键初始化/补齐国标标准科目表（后端幂等，不覆盖已有科目）。
API.initializeStandard = () => axios.post(`${API.url}/initialize_standard`);

export default API;
