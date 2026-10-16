import camelcaseKeys from 'camelcase-keys';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { buildMesReturnActions } from './_returnActions';

// 关闭 / 启用：后端回的是整张单，直接替掉列表里那条，不重拉整页
// （重拉的话当前页未必还包含这张单，按钮点完像是没反应）。
const buildCloseActions = API => {
  const act = async function act(call, id) {
    this.setUIFlag({ updatingItem: true });
    try {
      const { data } = await call(id);
      const record = camelcaseKeys(data || {}, { deep: true });
      const index = this.records.findIndex(r => r.id === record.id);
      if (index !== -1) this.records[index] = record;
      return record;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      this.setUIFlag({ updatingItem: false });
    }
  };
  return {
    closeOrder(id) {
      return act.call(this, API.close, id);
    },
    reopenOrder(id) {
      return act.call(this, API.reopen, id);
    },
  };
};

export const useMesPurchaseOrdersStore = buildCrmStore({
  name: 'mesPurchaseOrders',
  API: MesPurchaseOrderAPI,
  paramKey: 'purchase_order',
  extraActions: API => ({
    ...buildMesReturnActions(API),
    ...buildCloseActions(API),
  }),
});
