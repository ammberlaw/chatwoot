import OrgDepartmentAPI from 'dashboard/api/org/departments';
import { buildCrmStore } from '../crm/_crmStoreFactory';

export const useOrgDepartmentsStore = buildCrmStore({
  name: 'orgDepartments',
  API: OrgDepartmentAPI,
  paramKey: 'department',
});
