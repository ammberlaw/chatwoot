import OrgMembershipAPI from 'dashboard/api/org/memberships';
import { buildCrmStore } from '../crm/_crmStoreFactory';

export const useOrgMembershipsStore = buildCrmStore({
  name: 'orgMemberships',
  API: OrgMembershipAPI,
  paramKey: 'membership',
});
