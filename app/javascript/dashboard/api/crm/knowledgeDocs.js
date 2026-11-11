/* global axios */
import { buildCrmClient } from './_crmClient';
import Auth from '../auth';

const client = buildCrmClient('knowledge_docs');

// 图库：只列图片类附件，给报价单/PI 挑产品图（分区/分类筛选在前端做）。
client.imageLibrary = (params = {}) =>
  axios.get(`${client.url}/image_library?${new URLSearchParams(params)}`);

// 把选中的知识库文件在服务端复制一份，拿回 signed_id 当附件挂（见 Crm::KnowledgeDocSnapshot）。
client.snapshotFiles = fileIds =>
  axios.post(`${client.url}/snapshot_files`, { file_ids: fileIds });

// DeviseTokenAuth 支持表单参数认证。POST 凭证留在请求体，浏览器直接下载，
// 避免 axios/blob 把几百 MB 的 ZIP 全部攒在内存里，或将凭证放进 URL。
client.download = ({ docIds = [], categoryIds = [], ...params }) => {
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = client.url + '/download';
  form.target = '_blank';
  form.rel = 'noopener';
  form.hidden = true;
  const auth = Auth.getAuthData();
  const fields = {
    ...params,
    doc_ids: docIds.join(','),
    category_ids: categoryIds.join(','),
    'access-token': auth['access-token'],
    client: auth.client,
    uid: auth.uid,
  };
  Object.entries(fields).forEach(([name, value]) => {
    if (value === undefined || value === null) return;
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.appendChild(input);
  });
  document.body.appendChild(form);
  form.submit();
  form.remove();
};

client.uploaders = params =>
  axios.get(`${client.url}/uploaders?${new URLSearchParams(params)}`);
client.versions = id => axios.get(`${client.url}/${id}/versions`);
client.restoreVersion = (id, versionId) =>
  axios.post(`${client.url}/${id}/restore_version`, { version_id: versionId });
client.replaceFile = (id, data) =>
  axios.post(`${client.url}/${id}/replace_file`, data);
client.retryExtraction = id =>
  axios.post(`${client.url}/${id}/retry_extraction`);
client.preference = (id, favorite) =>
  axios.post(`${client.url}/${id}/preference`, { favorite });
client.opened = id => axios.post(`${client.url}/${id}/opened`);
client.maintainers = id => axios.get(`${client.url}/${id}/maintainers`);
client.bulk = payload => axios.post(`${client.url}/bulk`, payload);

export default client;
