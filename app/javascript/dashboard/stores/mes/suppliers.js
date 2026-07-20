import MesSupplierAPI from 'dashboard/api/mes/suppliers';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesSuppliersStore = buildCrmStore({
  name: 'mesSuppliers',
  API: MesSupplierAPI,
  paramKey: 'supplier',
});
