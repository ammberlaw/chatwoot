import ErpReceivableAPI from 'dashboard/api/erp/receivables';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useErpReceivablesStore = buildCrmStore({
  name: 'erpReceivables',
  API: ErpReceivableAPI,
  paramKey: 'receivable',
});
