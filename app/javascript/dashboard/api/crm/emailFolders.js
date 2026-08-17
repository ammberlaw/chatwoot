/* global axios */

// 邮件自定义文件夹（个人私有）。
const base = accountId => `/api/v1/accounts/${accountId}/crm/email_folders`;

export default {
  get(accountId) {
    return axios.get(base(accountId));
  },
  create(accountId, name, parentId = null) {
    return axios.post(base(accountId), { name, parent_id: parentId });
  },
  delete(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
  move(accountId, ids, emailFolderId) {
    return axios.post(
      `/api/v1/accounts/${accountId}/crm/emails/move_to_folder`,
      {
        ids,
        email_folder_id: emailFolderId,
      }
    );
  },
};
