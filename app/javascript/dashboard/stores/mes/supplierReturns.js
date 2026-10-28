import camelcaseKeys from 'camelcase-keys';
import MesSupplierReturnAPI from 'dashboard/api/mes/supplierReturns';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// 退出/登记返回后端都回整张单，直接替掉列表里那条，不重拉整页。
const replaceIn = (records, record) => {
  const i = records.findIndex(r => r.id === record.id);
  if (i !== -1) records[i] = record;
};

export const useMesSupplierReturnsStore = buildCrmStore({
  name: 'mesSupplierReturns',
  API: MesSupplierReturnAPI,
  paramKey: 'supplier_return',
  extraActions: API => ({
    async sendOut(id, sentOn) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await API.sendOut(id, sentOn);
        const record = camelcaseKeys(data || {}, { deep: true });
        replaceIn(this.records, record);
        return record;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },
    async receiveBack(id, rows, returnedOn, warehouseId) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await API.receiveBack(id, rows, returnedOn, warehouseId);
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
