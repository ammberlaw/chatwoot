import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import MesStockEntryAPI from 'dashboard/api/mes/stockEntries';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { buildMesReturnActions } from './_returnActions';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const normalizeMeta = meta => ({
  ...camelcaseKeys(meta || {}),
  count: Number(meta?.count || 0),
  currentPage: Number(meta?.current_page || meta?.currentPage || 1),
});

export const useMesStockEntriesStore = createStore({
  name: 'mesStockEntries',
  type: 'pinia',
  API: MesStockEntryAPI,
  getters: {
    getRecords: state => state.records,
  },
  actions: () => ({
    ...buildMesReturnActions(MesStockEntryAPI),

    async get(params = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await MesStockEntryAPI.get(params);
        this.records = camelize(data.payload);
        this.meta = normalizeMeta(data.meta);
        return this.records;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    // 原料↔成品转换：后端建单即过账，返回那张单。
    async convert(payload) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.convert(payload);
        return camelize(data);
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingItem: false });
      }
    },

    async create(obj) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.create({
          stock_entry: snakecaseKeys(obj, { deep: true }),
        });
        const record = camelize(data);
        this.records.unshift(record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingItem: false });
      }
    },

    // 仓库清点确认（确认即过账）：调用后就地替换记录。
    async confirmWarehouse(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.confirmWarehouse(id);
        const record = camelize(data);
        const index = this.records.findIndex(r => r.id === record.id);
        if (index !== -1) this.records[index] = record;
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    // 过账后就地替换（状态转 POSTED）。
    async post(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.post(id);
        const record = camelize(data);
        const index = this.records.findIndex(r => r.id === record.id);
        if (index !== -1) this.records[index] = record;
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    // 财务审核通过/驳回后就地替换（审核状态变了，过账按钮跟着亮/灭）。
    async approve(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.approve(id);
        const record = camelize(data);
        const index = this.records.findIndex(r => r.id === record.id);
        if (index !== -1) this.records[index] = record;
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    async reject(id, reason) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.reject(id, reason);
        const record = camelize(data);
        const index = this.records.findIndex(r => r.id === record.id);
        if (index !== -1) this.records[index] = record;
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    // 作废（冲销）后就地替换（状态转 CANCELLED，保留在列表可追溯）。
    async cancel(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesStockEntryAPI.cancel(id);
        const record = camelize(data);
        const index = this.records.findIndex(r => r.id === record.id);
        if (index !== -1) this.records[index] = record;
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    async delete(id) {
      this.setUIFlag({ deletingItem: true });
      try {
        await MesStockEntryAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
        return id;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ deletingItem: false });
      }
    },
  }),
});
