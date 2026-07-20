import MesWarehouseAPI from 'dashboard/api/mes/warehouses';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesWarehousesStore = buildCrmStore({
  name: 'mesWarehouses',
  API: MesWarehouseAPI,
  paramKey: 'warehouse',
});
