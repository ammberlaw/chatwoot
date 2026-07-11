import CrmOpportunityAPI from 'dashboard/api/crm/opportunities';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmOpportunitiesStore = buildCrmStore({
  name: 'crmOpportunities',
  API: CrmOpportunityAPI,
  paramKey: 'opportunity',
});
