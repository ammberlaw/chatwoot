import MesMaterialAPI from 'dashboard/api/mes/materials';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesMaterialsStore = buildCrmStore({
  name: 'mesMaterials',
  API: MesMaterialAPI,
  paramKey: 'material',
});
