import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmKpiSchemesStore = buildCrmStore({
  name: 'crmKpiSchemes',
  API: CrmKpiSchemeAPI,
  paramKey: 'scheme',
});
