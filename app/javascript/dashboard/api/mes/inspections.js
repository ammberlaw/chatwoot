/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('inspections');

// 录检验前把文件（视频/照片/附件）暂存为 blob，返回 signed_id。
client.stageBlob = formData =>
  axios.post(`${client.url}/stage_blob`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default client;
