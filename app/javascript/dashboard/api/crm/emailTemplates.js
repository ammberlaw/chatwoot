/* global axios */
import { buildCrmClient } from './_crmClient';

// 邮件模板：含附件时走 multipart（createWithFiles 基类已有，这里补 updateWithFiles）。
const api = buildCrmClient('email_templates');

api.updateWithFiles = (id, formData) =>
  axios.patch(`${api.url}/${id}`, formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export default api;
