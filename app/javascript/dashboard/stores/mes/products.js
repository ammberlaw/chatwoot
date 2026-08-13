import MesProductAPI from 'dashboard/api/mes/products';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesProductsStore = buildCrmStore({
  name: 'mesProducts',
  API: MesProductAPI,
  paramKey: 'product',
});
