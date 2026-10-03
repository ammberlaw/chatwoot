/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('knowledge_docs');

// 把选中的知识库文件在服务端复制一份，拿回 signed_id 当附件挂（见 Crm::KnowledgeDocSnapshot）。
client.snapshotFiles = fileIds =>
  axios.post(`${client.url}/snapshot_files`, { file_ids: fileIds });

export default client;
