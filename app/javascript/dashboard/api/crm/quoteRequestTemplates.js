import ApiClient from '../ApiClient';

// 定制报价的参数模板：每条产品线一套字段。仅管理员/副管可增删改。
class QuoteRequestTemplatesAPI extends ApiClient {
  constructor() {
    super('crm/quote_request_templates', { accountScoped: true });
  }
}

export default new QuoteRequestTemplatesAPI();
