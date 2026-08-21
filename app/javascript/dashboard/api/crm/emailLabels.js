/* global axios */

// 邮件标签定义（每账户一套）。邮件上的归属存 crm_emails.label_ids，打/去标签走 emails#update。
const base = accountId => `/api/v1/accounts/${accountId}/crm/email_labels`;

export default {
  get(accountId) {
    return axios.get(base(accountId));
  },
  create(accountId, { name, color }) {
    return axios.post(base(accountId), { label: { name, color } });
  },
  update(accountId, id, attrs) {
    return axios.patch(`${base(accountId)}/${id}`, { label: attrs });
  },
  delete(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
};
