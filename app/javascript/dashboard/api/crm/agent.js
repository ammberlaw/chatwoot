/* global axios */
import ApiClient from '../ApiClient';

// CRM AI 助手。跑一轮几十秒，所以 sendMessage 只是把任务丢进后台，
// 之后靠 show 轮询拿结果（会话 status=RUNNING 就接着等）。
class CrmAgentApi extends ApiClient {
  constructor() {
    super('crm/ai/agent', { accountScoped: true });
  }

  create(crmCustomerId) {
    return axios.post(this.url, {
      crm_customer_id: crmCustomerId || undefined,
    });
  }

  sendMessage(id, content) {
    return axios.post(`${this.url}/${id}/create_message`, { content });
  }
}

export default new CrmAgentApi();
