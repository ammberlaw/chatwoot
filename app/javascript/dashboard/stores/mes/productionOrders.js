import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const normalizeMeta = meta => ({
  ...camelcaseKeys(meta || {}),
  count: Number(meta?.count || 0),
  currentPage: Number(meta?.current_page || meta?.currentPage || 1),
});

export const useMesProductionOrdersStore = createStore({
  name: 'mesProductionOrders',
  type: 'pinia',
  API: MesProductionOrderAPI,
  getters: {
    getRecords: state => state.records,
  },
  actions: () => ({
    async get(params = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await MesProductionOrderAPI.get(params);
        this.records = camelize(data.payload);
        this.meta = normalizeMeta(data.meta);
        return this.records;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    // 从销售订单转生产订单，成功后插入列表头。
    async convert(payload) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.convert(
          snakecaseKeys(payload, { deep: true })
        );
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
        const { data } = await MesProductionOrderAPI.update(id, {
          production_order: snakecaseKeys(rest, { deep: true }),
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
        await MesProductionOrderAPI.delete(id);
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
