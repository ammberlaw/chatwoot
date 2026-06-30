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

  get(params = {}) {
    const { page = 1, filter, status, accountOwnerId } = params;
    const requestURL = `${this.url}?${buildParams({
      page,
      filter,
      status,
      account_owner_id: accountOwnerId,
    })}`;
    return axios.get(requestURL);
  }
}

export default new CrmCustomerAPI();
