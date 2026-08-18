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
};
