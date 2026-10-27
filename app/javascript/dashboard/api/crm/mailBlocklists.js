/* global axios */

// 收信黑名单：按发件域名/地址在入库前丢弃推销信（后端 Crm::MailBlocklist）。
const base = accountId => `/api/v1/accounts/${accountId}/crm/mail_blocklists`;

export default {
  // 返回 { payload: [规则…], suggestions: [{ value, spam_count }…] }
  get(accountId) {
    return axios.get(base(accountId));
  },
  // value：域名（example.com，含子域名一起拦）或完整邮箱（a@example.com，只拦这一个）。
  // scope：'global' 全公司（仅管理员，后端会再校验一次）/ 'mine' 只拦自己名下的信。
  create(accountId, value, note, scope = 'mine') {
    return axios.post(base(accountId), {
      mail_blocklist: { value, note, scope },
    });
  },
  delete(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
};
