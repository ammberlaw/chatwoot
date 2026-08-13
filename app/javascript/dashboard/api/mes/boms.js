/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('boms');

// 下发草稿 BOM → 正式生效。
client.release = id => axios.post(`${client.url}/${id}/release`);

// 建单前暂存文件为 blob，返回 signed_id。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// 编辑态直接挂载/移除附件（kind = images | files）。
client.attachFiles = (id, formData, kind = 'files') =>
  axios.post(`${client.url}/${id}/attach?kind=${kind}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
client.detachFile = (id, attachmentId, kind = 'files') =>
  axios.delete(`${client.url}/${id}/attach/${attachmentId}?kind=${kind}`);

export default client;
