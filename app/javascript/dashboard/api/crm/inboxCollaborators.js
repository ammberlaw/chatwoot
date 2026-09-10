/* global axios */
import ApiClient from '../ApiClient';

// 业务分配设置（超级管理员/副管理员）：读/存各收件箱的协作者
// = 会话「分配业务」下拉里能被选中的人。
class InboxCollaboratorsAPI extends ApiClient {
  constructor() {
    super('crm/inbox_collaborators', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  save(inboxId, userIds) {
    return axios.patch(this.url, { inbox_id: inboxId, user_ids: userIds });
  }
}

export default new InboxCollaboratorsAPI();
