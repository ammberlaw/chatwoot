/* global axios */
import ApiClient from '../ApiClient';

// 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定:支持一人多号。
class WhatsappWebAPI extends ApiClient {
  constructor() {
    super('crm/whatsapp_web', { accountScoped: true });
  }

  // 我名下所有号
  list() {
    return axios.get(this.url);
  }

  // 新增一个号(建收件箱并起会话,返回该号 QR)
  create() {
    return axios.post(this.url);
  }

  connect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/connect`);
  }

  status(inboxId) {
    return axios.get(`${this.url}/${inboxId}/status`);
  }

  disconnect(inboxId) {
    return axios.delete(`${this.url}/${inboxId}`);
  }

  remove(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/remove`);
  }

  // 输入手机号直接开聊：后端先查该号是否注册了 WhatsApp，再建/复用会话。
  startChat(inboxId, phone, name) {
    return axios.post(`${this.url}/${inboxId}/start_chat`, { phone, name });
  }
}

export default new WhatsappWebAPI();
