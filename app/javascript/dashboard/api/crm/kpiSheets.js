/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('kpi_sheets');

// 侧栏角标：等我动手的考核表数（待我填报/打分/人事确认/总经理确认）。
// 口径与每周催办同一份（后端 Crm::KpiReminderJob.actionable_for）。
client.pendingCount = () => axios.get(`${client.url}/pending_count`);

// 上传本方电子签 + 状态流转。signature 可为 File 或空。
const act = (id, action, signature) => {
  const fd = new FormData();
  if (signature) fd.append('signature', signature);
  return axios.post(`${client.url}/${id}/${action}`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

client.submit = (id, sig) => act(id, 'submit', sig);
client.score = (id, sig) => act(id, 'score', sig);
client.hrConfirm = (id, sig) => act(id, 'hr_confirm', sig);
client.gmConfirm = (id, sig) => act(id, 'gm_confirm', sig);

// AI 打分建议：为各指标算建议分（存入 suggested_score），返回 { suggestions: [{id, suggested_score, reason}] }。
client.aiSuggest = id => axios.post(`${client.url}/${id}/ai_suggest`);

// 退回重填：审批人带原因退回到「待填报」。
client.returnSheet = (id, reason) =>
  axios.post(`${client.url}/${id}/return_sheet`, { reason });

// 退回主管改分：待人事/总经理确认时退回到「待打分」，原因选填。
client.reopenScoring = (id, reason) =>
  axios.post(`${client.url}/${id}/reopen_scoring`, { reason });

export default client;
