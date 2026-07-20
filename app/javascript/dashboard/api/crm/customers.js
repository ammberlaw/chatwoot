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

  // 批量导入：rows 为前端映射好的行（键=CRM字段），defaultOwnerId 为统一负责人（可空）。
  import({ rows, defaultOwnerId }) {
    return axios.post(`${this.url}/import`, {
      rows,
      default_owner_id: defaultOwnerId || undefined,
    });
  }
}

export default new CrmCustomerAPI();
