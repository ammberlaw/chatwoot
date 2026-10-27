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

  // pageContext：用户提问那一刻开着哪一页（{ route, subject }）。
  // 后端据此理解「这张单」「这个客户」指的是谁，省掉一轮反问。
  sendMessage(id, content, pageContext) {
    return axios.post(`${this.url}/${id}/create_message`, {
      content,
      page_context: pageContext || undefined,
    });
  }
}

export default new CrmAgentApi();
