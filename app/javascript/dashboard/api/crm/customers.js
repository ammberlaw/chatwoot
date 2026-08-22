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

  // 添加到已有的顾客：把某来信邮箱收编为该客户的联系人（并补挂其散邮件）。
  attachContact(id, { email, name }) {
    return axios.post(`${this.url}/${id}/attach_contact`, { email, name });
  }

  // 客户合并：把 sourceId 客户合并进 id（存活方），迁移其邮件/订单/商机/跟进后删除 source。
  merge(id, sourceId) {
    return axios.post(`${this.url}/${id}/merge`, { source_id: sourceId });
  }

  // 流失预警角标：可见范围内超期未互动的成交客户数。
  churnRiskCount() {
    return axios.get(`${this.url}/churn_risk_count`);
  }

  // 列表顶部概览卡：客户数 / 本月新增 / 在谈商机 / 有成交订单（沿用当前视图筛选）。
  stats(params = {}) {
    const query = buildParams(params);
    return axios.get(
      query ? `${this.url}/stats?${query}` : `${this.url}/stats`
    );
  }

  // 特别关注（每人各标）：收藏 / 取消收藏。
  favorite(id) {
    return axios.post(`${this.url}/${id}/favorite`);
  }

  unfavorite(id) {
    return axios.delete(`${this.url}/${id}/favorite`);
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
