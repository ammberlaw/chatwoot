/* global axios */
import ApiClient from '../ApiClient';

class PettyCashAPI extends ApiClient {
  constructor() {
    super('crm/petty_cash_books', { accountScoped: true });
  }

  // 台账本
  books() {
    return axios.get(this.url);
  }

  createBook(book) {
    return axios.post(this.url, { book });
  }

  updateBook(id, book) {
    return axios.patch(`${this.url}/${id}`, { book });
  }

  deleteBook(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // 流水（挂在某本账下）；month 传 YYYY-MM 只看该月。
  entries(bookId, params = {}) {
    return axios.get(`${this.url}/${bookId}/petty_cash_entries`, { params });
  }

  createEntry(bookId, entry) {
    return axios.post(`${this.url}/${bookId}/petty_cash_entries`, { entry });
  }

  // 带票据走 multipart（后端 attach 追加，不动已有附件）。
  createEntryWithFiles(bookId, formData) {
    return axios.post(`${this.url}/${bookId}/petty_cash_entries`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  updateEntry(bookId, id, entry) {
    return axios.patch(`${this.url}/${bookId}/petty_cash_entries/${id}`, {
      entry,
    });
  }

  updateEntryWithFiles(bookId, id, formData) {
    return axios.patch(
      `${this.url}/${bookId}/petty_cash_entries/${id}`,
      formData,
      { headers: { 'Content-Type': 'multipart/form-data' } }
    );
  }

  deleteEntry(bookId, id) {
    return axios.delete(`${this.url}/${bookId}/petty_cash_entries/${id}`);
  }
}

export default new PettyCashAPI();
