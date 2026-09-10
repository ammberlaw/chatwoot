/* global axios */
import ApiClient from '../ApiClient';

// CRM 岗位权限模板：管理员自定义「岗位 = 系统角色 + 模块 + MES 岗位 + 财务」，成员权限页一键套用。
class RoleTemplatesAPI extends ApiClient {
  constructor() {
    super('crm/role_templates', { accountScoped: true });
  }

  createTemplate(payload) {
    return axios.post(this.url, { role_template: payload });
  }

  updateTemplate(id, payload) {
    return axios.patch(`${this.url}/${id}`, { role_template: payload });
  }

  deleteTemplate(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new RoleTemplatesAPI();
