/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('mail_accounts');
// 连通性检测：实测该账户 SMTP（发信）/IMAP（收信）认证是否通过。
client.test = id => axios.post(`${client.url}/${id}/test`);

export default client;
