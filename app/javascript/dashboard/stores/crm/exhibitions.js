import CrmExhibitionAPI from 'dashboard/api/crm/exhibitions';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmExhibitionsStore = buildCrmStore({
  name: 'crmExhibitions',
  API: CrmExhibitionAPI,
  paramKey: 'exhibition',
});
