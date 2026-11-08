/* global axios */
import ApiClient from '../ApiClient';

// 线索池里的单条操作。解锁会扣 Apollo credits，所以界面上是人工点一条解一条。
class CrmLeadsAPI extends ApiClient {
  constructor() {
    super('crm/leads', { accountScoped: true });
  }

  unlock(id) {
    return axios.post(`${this.url}/${id}/unlock`);
  }

  // 从共享池领取（归属自己，保护期内别人看不见）。和 claim（建档）是两件事。
  take(id) {
    return axios.post(`${this.url}/${id}/take`);
  }

  // 放回池子：我暂时跟不了，让别人去跟。和丢弃（这家不是买家）含义不同。
  release(id) {
    return axios.post(`${this.url}/${id}/release`);
  }

  claim(id) {
    return axios.post(`${this.url}/${id}/claim`);
  }

  // reason 是原因码（RIVAL/SIZE/…），给 AI 初筛学方向用，不传也能丢。
  discard(id, reason = null) {
    return axios.post(`${this.url}/${id}/discard`, reason ? { reason } : {});
  }

  // 一键 AI 背调：抓官网 + Apollo 企业库，实测 17~30 秒。
  // **异步**：这个请求只是排队，立刻返回；跑完要靠 show 轮询。
  // 动作名以 ai_ 开头是为了吃到 rack_timeout 的 AI 放宽，别改。
  bgCheck(id) {
    return axios.post(`${this.url}/${id}/ai_bg_check`);
  }

  // 轮询单条线索，看背调跑完没有。
  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new CrmLeadsAPI();
