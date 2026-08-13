/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('notifications');

// 未读数（侧栏角标）。
client.unreadCount = () => axios.get(`${client.url}/unread_count`);
// 标记单条 / 全部已读。
client.markRead = id => axios.post(`${client.url}/${id}/mark_read`);
client.markAllRead = () => axios.post(`${client.url}/mark_all_read`);

export default client;
