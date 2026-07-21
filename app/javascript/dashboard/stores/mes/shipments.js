import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import MesShipmentAPI from 'dashboard/api/mes/shipments';
import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const normalizeMeta = meta => ({
  ...camelcaseKeys(meta || {}),
  count: Number(meta?.count || 0),
  currentPage: Number(meta?.current_page || meta?.currentPage || 1),
});

const replace = (records, record) => {
  const index = records.findIndex(r => r.id === record.id);
  if (index !== -1) records[index] = record;
};

export const useMesShipmentsStore = createStore({
  name: 'mesShipments',
  type: 'pinia',
  API: MesShipmentAPI,
  getters: {
    getRecords: state => state.records,
  },
  actions: () => ({
    async get(params = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await MesShipmentAPI.get(params);
        this.records = camelize(data.payload);
        this.meta = normalizeMeta(data.meta);
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
        const { data } = await MesShipmentAPI.create({
          shipment: snakecaseKeys(obj, { deep: true }),
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

    async notify(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesShipmentAPI.notify(id);
        const record = camelize(data);
        replace(this.records, record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    async ship(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesShipmentAPI.ship(id);
        const record = camelize(data);
        replace(this.records, record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },
  }),
});
