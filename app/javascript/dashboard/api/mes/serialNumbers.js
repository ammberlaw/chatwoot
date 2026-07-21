/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('serial_numbers');

// 按工单登记 SN（count 生成 或 sns 明细）。
client.register = payload => axios.post(client.url, payload);
// 追溯：SN → 工单/BOM/客户/出库。
client.trace = sn => axios.get(`${client.url}/trace`, { params: { sn } });

export default client;
