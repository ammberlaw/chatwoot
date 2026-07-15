/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('kpi_schemes');

// 下发：为选中员工生成当月考核表。
client.distribute = (id, ownerIds) =>
  axios.post(`${client.url}/${id}/distribute`, { owner_ids: ownerIds });

export default client;
