import CrmEmailSignatureAPI from 'dashboard/api/crm/emailSignatures';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmEmailSignaturesStore = buildCrmStore({
  name: 'crmEmailSignatures',
  API: CrmEmailSignatureAPI,
  paramKey: 'email_signature',
});
