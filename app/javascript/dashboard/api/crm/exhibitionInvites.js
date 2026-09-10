/* global axios */
import ApiClient from '../ApiClient';

// 展会邀约记录：AI 生成邀请函 / 阶段流转 / 移出名单。
class ExhibitionInvitesAPI extends ApiClient {
  constructor() {
    super('crm/exhibition_invites', { accountScoped: true });
  }

  compose(id) {
    return axios.post(`${this.url}/${id}/compose`);
  }

  advance(id, stage) {
    return axios.post(`${this.url}/${id}/advance`, { stage });
  }
}

export default new ExhibitionInvitesAPI();
