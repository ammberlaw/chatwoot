/* global axios */
import ApiClient from '../ApiClient';

// 邮件 AI 助手（DeepSeek）：写信 / 来信翻译 / 往来摘要。同步生成，调用方自己转圈。
class CrmAiAPI extends ApiClient {
  constructor() {
    super('crm/ai', { accountScoped: true });
  }

  // 写信/回信：intent=中文意图；original=回复场景带上的原文引用（可选）。
  compose({ intent, original }) {
    return axios.post(`${this.url}/compose`, { intent, original });
  }

  // 整封翻译成中文（按邮件 id，正文后端取）。
  translate(emailId) {
    return axios.post(`${this.url}/translate`, { email_id: emailId });
  }

  // 与某个对方地址的往来摘要。
  summarize(address) {
    return axios.post(`${this.url}/summarize`, { address });
  }

  // 客户 AI 背调：输入邮箱→抓官网→判断公司背景 + 查库是否已建档。
  companyLookup(email) {
    return axios.post(`${this.url}/company_lookup`, { email });
  }
}

export default new CrmAiAPI();
