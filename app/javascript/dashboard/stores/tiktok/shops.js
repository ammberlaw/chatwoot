import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import TiktokShopsAPI from 'dashboard/api/tiktok/shops';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

export const useTiktokShopsStore = createStore({
  name: 'tiktokShops',
  type: 'pinia',
  API: TiktokShopsAPI,
  getters: {
    getShops: state => state.records,
    activeShops: state => state.records.filter(s => s.active),
  },
  actions: () => ({
    async get() {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await TiktokShopsAPI.get();
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
        const { data } = await TiktokShopsAPI.create({
          shop: snakecaseKeys(obj, { deep: true }),
        });
        const record = camelize(data);
        this.records.push(record);
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
        const { data } = await TiktokShopsAPI.update(id, {
          shop: snakecaseKeys(rest, { deep: true }),
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
        await TiktokShopsAPI.delete(id);
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
