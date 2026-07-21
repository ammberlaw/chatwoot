import MesInspectionAPI from 'dashboard/api/mes/inspections';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useMesInspectionsStore = buildCrmStore({
  name: 'mesInspections',
  API: MesInspectionAPI,
  paramKey: 'inspection',
});
