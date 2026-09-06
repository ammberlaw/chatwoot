import ErpVoucherAPI from 'dashboard/api/erp/vouchers';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useErpVouchersStore = buildCrmStore({
  name: 'erpVouchers',
  API: ErpVoucherAPI,
  paramKey: 'voucher',
});
