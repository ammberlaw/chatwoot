/* global axios */
import { buildOrgClient } from './_orgClient';

const client = buildOrgClient('departments');

// 同级排序：ids 为有序的部门 id 数组。
client.reorder = ids => axios.post(`${client.url}/reorder`, { positions: ids });

export default client;
