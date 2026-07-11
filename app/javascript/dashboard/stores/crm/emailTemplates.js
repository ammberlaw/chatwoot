import CrmEmailTemplateAPI from 'dashboard/api/crm/emailTemplates';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmEmailTemplatesStore = buildCrmStore({
  name: 'crmEmailTemplates',
  API: CrmEmailTemplateAPI,
  paramKey: 'template',
});
