import ErpPayableAPI from 'dashboard/api/erp/payables';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useErpPayablesStore = buildCrmStore({
  name: 'erpPayables',
  API: ErpPayableAPI,
  paramKey: 'payable',
});
