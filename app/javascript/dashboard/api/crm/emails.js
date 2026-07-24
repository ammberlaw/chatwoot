/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('emails');

const qs = params => {
  const q = new URLSearchParams(params).toString();
  return q ? `?${q}` : '';
};

// 左栏文件夹角标：各文件夹总数 + 未读数。可按 owner_id/mailbox 过滤（我的/团队/邮箱）。
client.counts = (params = {}) => axios.get(`${client.url}/counts${qs(params)}`);

// 可见范围内的邮箱列表 + 各自未读数（左栏「全部收件 + 各邮箱」切换）。
client.mailboxes = (params = {}) =>
  axios.get(`${client.url}/mailboxes${qs(params)}`);

// 知识库附件快照：把选中的知识库文件复制进这封邮件的附件。
client.attachKb = (id, fileIds) =>
  axios.post(`${client.url}/${id}/attach_kb`, { file_ids: fileIds });

// 阅读追踪明细：每次打开的时间 + IP + UA。
client.opens = id => axios.get(`${client.url}/${id}/opens`);

// 手动收取：立即为当前用户邮箱排拉取任务（比每分钟轮询更实时）。
client.fetchNow = () => axios.post(`${client.url}/fetch`);

// 作为附件转发：拿本邮件的 .eml（RFC822）二进制，前端包成 File 当新邮件附件。
client.eml = id =>
  axios.get(`${client.url}/${id}/eml`, { responseType: 'blob' });

// 就地更新草稿并追加新附件（multipart）：后端 update 会 attach 追加，不动已有附件。
client.updateWithFiles = (id, formData) =>
  axios.patch(`${client.url}/${id}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default client;
