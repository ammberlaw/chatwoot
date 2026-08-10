import ApiClient from '../ApiClient';

// TikTok 部门（团队式：负责人+成员）。CRUD 走 ApiClient 默认方法。
class TiktokDepartmentsAPI extends ApiClient {
  constructor() {
    super('tiktok/departments', { accountScoped: true });
  }
}

export default new TiktokDepartmentsAPI();
