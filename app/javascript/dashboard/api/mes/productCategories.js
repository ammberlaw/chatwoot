/* global axios */
import ApiClient from '../ApiClient';

// 商品类别树（产品线 → 商品类别 + 各自条数）。
// 数据源就是产品档案的 source_category，也就是金蝶那列「商品类别」——
// 不另起一套要人工维护、迟早和金蝶对不上的分类字典。
class ProductCategoriesAPI extends ApiClient {
  constructor() {
    super('mes/products', { accountScoped: true });
  }

  tree() {
    return axios.get(`${this.url}/categories`);
  }
}

export default new ProductCategoriesAPI();
