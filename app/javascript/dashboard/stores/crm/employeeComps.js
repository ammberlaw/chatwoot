import CrmEmployeeCompAPI from 'dashboard/api/crm/employeeComps';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmEmployeeCompsStore = buildCrmStore({
  name: 'crmEmployeeComps',
  API: CrmEmployeeCompAPI,
  paramKey: 'comp',
});
