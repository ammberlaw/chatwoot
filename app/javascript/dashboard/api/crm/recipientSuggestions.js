/* global axios */
// 写邮件收件人输入联想：按输入词返回「我的客户联系人」+「同事」，type 区分来源。
export default {
  search(accountId, q) {
    return axios.get(
      `/api/v1/accounts/${accountId}/crm/recipient_suggestions`,
      { params: { q } }
    );
  },
};
