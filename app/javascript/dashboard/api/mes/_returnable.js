/* global axios */
// 给 MES 操作单据客户端挂上「退回上一环节 / 重新激活」两个动作。
export const withReturnActions = client => {
  client.returnDocument = (id, reason) =>
    axios.post(`${client.url}/${id}/return_document`, { reason });
  client.reactivate = id => axios.post(`${client.url}/${id}/reactivate`);
  return client;
};
