/* global axios */
import ApiClient from '../ApiClient';

// 核价表（内部报价单）：按版本维护；明细随版本整表提交。
class CrmPriceListAPI extends ApiClient {
  constructor() {
    super('crm/price_lists', { accountScoped: true });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  // 复制成草稿：调价时不用重录整张表。
  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  // 上传公司现成的核价 Excel：一个 sheet 建一条产品线草稿。
  importFile(file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/import`, form);
  }

  // 跨产品线搜型号。
  search(q) {
    return axios.get(`${this.url}/search`, { params: { q } });
  }

  // 与上一版对比。
  diff(id) {
    return axios.get(`${this.url}/${id}/diff`);
  }

  // 公司文档里的图片（挑产品图用）。
  docImages({ q = '', sectionId = '' } = {}) {
    return axios.get(`${this.url}/doc_images`, {
      params: { q, section_id: sectionId },
    });
  }

  // 从公司文档选一张图挂到某行。
  imageFromDoc(id, itemId, attachmentId) {
    return axios.post(`${this.url}/${id}/items/${itemId}/image_from_doc`, {
      attachment_id: attachmentId,
    });
  }

  // 某一行挂产品图。
  uploadImage(id, itemId, file) {
    const form = new FormData();
    form.append('file', file);
    return axios.post(`${this.url}/${id}/items/${itemId}/image`, form);
  }

  // 导出 PDF 必须走 axios 拿 blob：接口是 api_access_token 头鉴权，
  // 浏览器直接开链接不带头，会被当成未登录。
  exportPdf(id) {
    return axios.get(`${this.url}/${id}/export_pdf`, { responseType: 'blob' });
  }
}

export default new CrmPriceListAPI();
