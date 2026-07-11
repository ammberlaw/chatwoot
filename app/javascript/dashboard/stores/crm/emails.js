import CrmEmailAPI from 'dashboard/api/crm/emails';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmEmailsStore = buildCrmStore({
  name: 'crmEmails',
  API: CrmEmailAPI,
  paramKey: 'email',
});
