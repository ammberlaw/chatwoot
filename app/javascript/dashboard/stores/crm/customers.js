import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { fetchCrmList } from './_crmStoreFactory';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

export const useCrmCustomersStore = createStore({
  name: 'crmCustomers',
  type: 'pinia',
  API: CrmCustomerAPI,
  getters: {
    getCustomers: state => state.records,
  },
  actions: () => ({
    get(params = {}) {
      return fetchCrmList(this, () => CrmCustomerAPI.get(params));
    },

    async create(obj) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await CrmCustomerAPI.create({
          customer: snakecaseKeys(obj, { deep: true }),
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
        const { data } = await CrmCustomerAPI.update(id, {
          customer: snakecaseKeys(rest, { deep: true }),
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
        await CrmCustomerAPI.delete(id);
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
