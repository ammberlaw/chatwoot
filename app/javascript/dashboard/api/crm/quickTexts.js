/* global axios */

// 快速文本（个人常用片段）：写邮件时一键插入正文。
const base = accountId => `/api/v1/accounts/${accountId}/crm/quick_texts`;

export default {
  get(accountId, params = {}) {
    return axios.get(base(accountId), { params });
  },
  create(accountId, payload) {
    return axios.post(base(accountId), { quick_text: payload });
  },
  update(accountId, id, payload) {
    return axios.patch(`${base(accountId)}/${id}`, { quick_text: payload });
  },
  delete(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
};
