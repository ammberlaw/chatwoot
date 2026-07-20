/* global axios */
import ApiClient from '../ApiClient';

// 我的个人签名（单数资源）：get 取自己的签名，save 上传/替换，remove 删除。
class SignatureAPI extends ApiClient {
  constructor() {
    super('crm/signature', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  save(imageFile) {
    const fd = new FormData();
    fd.append('image', imageFile);
    return axios.post(this.url, fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  remove() {
    return axios.delete(this.url);
  }
}

export default new SignatureAPI();
