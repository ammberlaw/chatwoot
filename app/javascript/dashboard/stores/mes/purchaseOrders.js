import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesPurchaseOrdersStore = buildCrmStore({
  name: 'mesPurchaseOrders',
  API: MesPurchaseOrderAPI,
  paramKey: 'purchase_order',
});
