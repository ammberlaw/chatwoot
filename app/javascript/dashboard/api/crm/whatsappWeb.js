/* global axios */
import ApiClient from '../ApiClient';

// 业务员个人 WhatsApp 号(WhatsApp Web/Baileys)绑定：扫码/状态/解绑。
class WhatsappWebAPI extends ApiClient {
  constructor() {
    super('crm/whatsapp_web', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  connect() {
    return axios.post(`${this.url}/connect`);
  }

  status() {
    return axios.get(`${this.url}/status`);
  }

  disconnect() {
    return axios.delete(this.url);
  }
}

export default new WhatsappWebAPI();
