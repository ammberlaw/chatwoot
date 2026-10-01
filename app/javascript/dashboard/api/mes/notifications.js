/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('notifications');

// 未读数（侧栏角标）。module=erp 只数财务通知，缺省只数生产通知——
// 口径必须和列表一致，否则角标说 6 条、点进去只有 2 条。
client.unreadCount = (params = {}) =>
  axios.get(`${client.url}/unread_count`, { params });
// 标记单条 / 全部已读。
client.markRead = id => axios.post(`${client.url}/${id}/mark_read`);
client.markAllRead = (params = {}) =>
  axios.post(`${client.url}/mark_all_read`, null, { params });

export default client;
