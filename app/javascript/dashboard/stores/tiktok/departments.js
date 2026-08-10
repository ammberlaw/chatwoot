import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import TiktokDepartmentsAPI from 'dashboard/api/tiktok/departments';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

export const useTiktokDepartmentsStore = createStore({
  name: 'tiktokDepartments',
  type: 'pinia',
  API: TiktokDepartmentsAPI,
  getters: {
    getDepartments: state => state.records,
  },
  actions: () => ({
    async get() {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await TiktokDepartmentsAPI.get();
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
        const { data } = await TiktokDepartmentsAPI.create({
          department: snakecaseKeys(obj, { deep: true }),
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
        const { data } = await TiktokDepartmentsAPI.update(id, {
          department: snakecaseKeys(rest, { deep: true }),
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
        await TiktokDepartmentsAPI.delete(id);
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
