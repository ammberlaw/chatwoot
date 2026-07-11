import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmSalesOrdersStore = buildCrmStore({
  name: 'crmSalesOrders',
  API: CrmSalesOrderAPI,
  paramKey: 'sales_order',
});
