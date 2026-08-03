/* global axios */
import ApiClient from '../ApiClient';

// 邮件 AI 助手设置（仅管理员）：读/存 DeepSeek key、模型、可选端点 + 测试连接。
class AiSettingsAPI extends ApiClient {
  constructor() {
    super('crm/ai_settings', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateSetting(payload) {
    return axios.patch(this.url, payload);
  }

  // 测试连接：传当前表单值（未保存也能验）；后端空则回退已保存配置。
  test(payload) {
    return axios.post(`${this.url}/test`, payload);
  }
}

export default new AiSettingsAPI();
