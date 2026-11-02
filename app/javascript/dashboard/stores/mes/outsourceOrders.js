import camelcaseKeys from 'camelcase-keys';
import MesOutsourceOrderAPI from 'dashboard/api/mes/outsourceOrders';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// 确认/关闭后端都回整张单，直接替掉列表里那条，不重拉整页。
const replaceIn = (records, record) => {
  const i = records.findIndex(r => r.id === record.id);
  if (i !== -1) records[i] = record;
};

export const useMesOutsourceOrdersStore = buildCrmStore({
  name: 'mesOutsourceOrders',
  API: MesOutsourceOrderAPI,
  paramKey: 'outsource_order',
  extraActions: API => ({
    async createFromProductionOrder(productionOrderId, attrs) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await API.createFromProductionOrder(
          productionOrderId,
          attrs
        );
        const record = camelcaseKeys(data || {}, { deep: true });
        this.records.unshift(record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingItem: false });
      }
    },
    async changeStatus(id, action) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await API[action](id);
        const record = camelcaseKeys(data || {}, { deep: true });
        replaceIn(this.records, record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },
  }),
});
