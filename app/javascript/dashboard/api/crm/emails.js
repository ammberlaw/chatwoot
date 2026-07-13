/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('emails');

// 左栏文件夹角标：各文件夹总数 + 未读数。
client.counts = () => axios.get(`${client.url}/counts`);

// 知识库附件快照：把选中的知识库文件复制进这封邮件的附件。
client.attachKb = (id, fileIds) =>
  axios.post(`${client.url}/${id}/attach_kb`, { file_ids: fileIds });

export default client;
