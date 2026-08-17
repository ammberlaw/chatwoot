/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('kpi_schemes');

// 下发：为选中员工生成当月考核表。
client.distribute = (id, ownerIds) =>
  axios.post(`${client.url}/${id}/distribute`, { owner_ids: ownerIds });

// 复制方案：整份拷贝出一份「(副本)」草稿。
client.duplicate = id => axios.post(`${client.url}/${id}/duplicate`);

export default client;
