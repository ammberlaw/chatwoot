/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('kpi_sheets');

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

export default client;
