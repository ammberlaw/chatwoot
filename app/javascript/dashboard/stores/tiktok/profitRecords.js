import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import TiktokProfitRecordsAPI from 'dashboard/api/tiktok/profitRecords';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

export const useTiktokProfitRecordsStore = createStore({
  name: 'tiktokProfitRecords',
  type: 'pinia',
  API: TiktokProfitRecordsAPI,
  getters: {
    getRecords: state => state.records,
  },
  actions: () => ({
    async get(params = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await TiktokProfitRecordsAPI.get(params);
        this.records = camelize(data.payload);
        return this.records;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    async create(obj) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await TiktokProfitRecordsAPI.create({
          profit_record: snakecaseKeys(obj, { deep: true }),
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

    async update({ id, ...rest }) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await TiktokProfitRecordsAPI.update(id, {
          profit_record: snakecaseKeys(rest, { deep: true }),
        });
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
        await TiktokProfitRecordsAPI.delete(id);
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
