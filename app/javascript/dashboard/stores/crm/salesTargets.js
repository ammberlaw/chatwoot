import CrmSalesTargetAPI from 'dashboard/api/crm/salesTargets';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmSalesTargetsStore = buildCrmStore({
  name: 'crmSalesTargets',
  API: CrmSalesTargetAPI,
  paramKey: 'target',
});
