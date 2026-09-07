/* global axios */
import ApiClient from '../ApiClient';

// 会话自动翻译：保存会话级设置（开关/对方语言）+ 外发中文译成对方语言。
class ConversationTranslationAPI extends ApiClient {
  constructor() {
    super('crm/conversation_translation', { accountScoped: true });
  }

  saveSettings(conversationId, { autoTranslate, targetLanguage }) {
    return axios.patch(`${this.url}/${conversationId}/settings`, {
      auto_translate: autoTranslate,
      target_language: targetLanguage,
    });
  }

  translate(conversationId, text, language) {
    return axios.post(`${this.url}/${conversationId}/translate`, {
      text,
      language,
    });
  }
}

export default new ConversationTranslationAPI();
