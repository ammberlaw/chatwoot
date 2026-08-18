/* global axios */

// 日程 Schedule：个人日历事件（可邀参与人、支持重复）。全员可用。
const base = accountId => `/api/v1/accounts/${accountId}/crm/schedule_events`;

export default {
  // params: { from, to } —— ISO 日期窗口，返回展开后的发生（含重复）。
  get(accountId, params = {}) {
    return axios.get(base(accountId), { params });
  },
  create(accountId, payload) {
    return axios.post(base(accountId), { schedule_event: payload });
  },
  update(accountId, id, payload) {
    return axios.patch(`${base(accountId)}/${id}`, { schedule_event: payload });
  },
  delete(accountId, id) {
    return axios.delete(`${base(accountId)}/${id}`);
  },
  // 按发生日期切换完成（重复日程按次）。
  toggleDone(accountId, id, date) {
    return axios.post(`${base(accountId)}/${id}/toggle_done`, { date });
  },
  // 侧栏角标：今日到期 + 已逾期未完成的日程数。
  pendingCount(accountId) {
    return axios.get(`${base(accountId)}/pending_count`);
  },
  // 在日程里完成一条跟进提醒：写跟进记录 + 顺延/清除提醒。
  // payload: { body, follow_up_method, result_tag, next_follow_up_at }
  completeFollowUp(accountId, id, payload) {
    return axios.post(`${base(accountId)}/${id}/complete_follow_up`, payload);
  },
};
