/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('exhibitions');

// 展会详情（含邀约名单）。
api.show = id => axios.get(`${api.url}/${id}`);
// 匹配潜客（按国家/地区）；include_low=true 时把低匹配也带上。
api.candidates = (id, params = {}) =>
  axios.get(`${api.url}/${id}/candidates`, { params });
// 加入邀约名单。
api.addInvites = (id, customerIds) =>
  axios.post(`${api.url}/${id}/add_invites`, { customer_ids: customerIds });
// 从 Apollo 企业库找新买家（按国家/关键词），滤掉 CRM 已有。
api.apolloSearch = (id, params = {}) =>
  axios.get(`${api.url}/${id}/apollo_search`, { params });
// 选中的 Apollo 公司建档 + 入邀约名单。
api.addApolloInvites = (id, companies) =>
  axios.post(`${api.url}/${id}/add_apollo_invites`, { companies });
// 4 步 SOP 分步群发：对选中邀约生成该步邮件草稿到邮件中心。
api.generateSopDrafts = (id, stage, inviteIds) =>
  axios.post(`${api.url}/${id}/generate_sop_drafts`, {
    stage,
    invite_ids: inviteIds,
  });

export default api;
