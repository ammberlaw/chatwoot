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
  // file：展会上拍的规格表、客户发来的实物照，或者客户直接丢过来的 PI / 报价表 /
  // 规格书。带附件时走 multipart——后端收到会先把图读成文字、把文档抽成正文
  // 再喂给 agent（它的工具都是查库的，没一个能看图或读文件）。
  sendMessage(id, content, pageContext, file) {
    if (!file) {
      return axios.post(`${this.url}/${id}/create_message`, {
        content,
        page_context: pageContext || undefined,
      });
    }
    const form = new FormData();
    form.append('content', content || '');
    form.append('attachment', file);
    if (pageContext?.route) form.append('page_context[route]', pageContext.route);
    if (pageContext?.subject) form.append('page_context[subject]', pageContext.subject);
    return axios.post(`${this.url}/${id}/create_message`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new CrmAgentApi();
