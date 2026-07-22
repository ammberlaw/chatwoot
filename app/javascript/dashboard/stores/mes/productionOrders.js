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

    // 新建定制生产订单（含 spec 规格），成功后插入列表头。
    async create(payload) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.create({
          production_order: snakecaseKeys(payload, { deep: true }),
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

    // 挂工程 BOM，返回更新后的生产订单并就地替换。
    async attachBom({ id, ...payload }) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.attachBom(
          id,
          snakecaseKeys(payload, { deep: true })
        );
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

    // 下发到采购阶段，返回更新后的生产订单并就地替换。
    async releasePurchasing(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.releasePurchasing(id);
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

    // 接单：本阶段负责人确认接手，替换列表中的记录。
    async acknowledge(id) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.acknowledge(id);
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

    // 拒收打回：退回上一阶段，替换列表中的记录。
    async reject({ id, reason }) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await MesProductionOrderAPI.reject(id, reason);
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
