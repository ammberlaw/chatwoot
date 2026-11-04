/* global axios */
import { buildCrmClient } from './_crmClient';

const api = buildCrmClient('payroll_sheets');

// 导入走 multipart；确认/退回是状态流转。
api.import = (file, { periodMonth, template, title } = {}) => {
  const fd = new FormData();
  fd.append('file', file);
  if (periodMonth) fd.append('period_month', periodMonth);
  if (template) fd.append('template', template);
  if (title) fd.append('title', title);
  return axios.post(`${api.url}/import`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
api.confirm = id => axios.post(`${api.url}/${id}/confirm`);
api.reopen = id => axios.post(`${api.url}/${id}/reopen`);

export default api;
