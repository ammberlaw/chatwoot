/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== ''
    )
  ).toString();

class CrmCustomerAPI extends ApiClient {
  constructor() {
    super('crm/customers', { accountScoped: true });
  }

  // 透传全部查询参数（page/filter/customer_group/product_group/q/team_id/
  // account_owner_id/sort/direction…）；buildParams 会滤掉 undefined/空值。
  get(params = {}) {
    const query = buildParams({ page: 1, ...params });
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }

  // 存量查重：四个维度（邮箱/电话/WhatsApp/同名）的重复分组。
  duplicates() {
    return axios.get(`${this.url}/duplicates`);
  }

  // 主动查重检索：scope=all/name/code/email/email_suffix/contact/phone/social。
  dedupeSearch({ scope, q }) {
    const query = buildParams({ scope, q });
    return axios.get(`${this.url}/dedupe_search?${query}`);
  }

  // 邮箱身份识别：colleague / mine / other(撞单) / stranger。
  identify(email) {
    return axios.get(`${this.url}/identify?${buildParams({ email })}`);
  }

  // 批量导入：rows 为前端映射好的行（键=CRM字段），defaultOwnerId 为统一负责人（可空）。
  import({ rows, defaultOwnerId }) {
    return axios.post(`${this.url}/import`, {
      rows,
      default_owner_id: defaultOwnerId || undefined,
    });
  }
}

export default new CrmCustomerAPI();
