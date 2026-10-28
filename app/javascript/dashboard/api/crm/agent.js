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
  // image：展会上拍的规格表、手写询价、客户发来的实物照。带图时走 multipart——
  // 后端收到会先用视觉模型把图读成文字再喂给 agent（它的工具都是查库的，没一个能看图）。
  sendMessage(id, content, pageContext, image) {
    if (!image) {
      return axios.post(`${this.url}/${id}/create_message`, {
        content,
        page_context: pageContext || undefined,
      });
    }
    const form = new FormData();
    form.append('content', content || '');
    form.append('image', image);
    if (pageContext?.route) form.append('page_context[route]', pageContext.route);
    if (pageContext?.subject) form.append('page_context[subject]', pageContext.subject);
    return axios.post(`${this.url}/${id}/create_message`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new CrmAgentApi();
