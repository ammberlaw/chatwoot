/* global axios */
import { buildCrmClient } from './_crmClient';

// CRM 成员权限：列出账号成员并分配 CRM 角色（仅管理员）。
const client = buildCrmClient('members');

// 停用（离职）：交接名下客户/商机 + 置无角色 + 禁止登录。可恢复。
client.deactivate = (id, payload = {}) =>
  axios.post(`${client.url}/${id}/deactivate`, payload);
client.reactivate = id => axios.post(`${client.url}/${id}/reactivate`);

export default client;
