/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('knowledge_docs');

// 图库：只列图片类附件，给报价单/PI 挑产品图（分区/分类筛选在前端做）。
client.imageLibrary = (params = {}) =>
  axios.get(`${client.url}/image_library?${new URLSearchParams(params)}`);

// 把选中的知识库文件在服务端复制一份，拿回 signed_id 当附件挂（见 Crm::KnowledgeDocSnapshot）。
client.snapshotFiles = fileIds =>
  axios.post(`${client.url}/snapshot_files`, { file_ids: fileIds });

export default client;
