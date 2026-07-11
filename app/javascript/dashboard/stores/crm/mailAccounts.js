import CrmMailAccountAPI from 'dashboard/api/crm/mailAccounts';
import { buildCrmStore } from './_crmStoreFactory';

export const useCrmMailAccountsStore = buildCrmStore({
  name: 'crmMailAccounts',
  API: CrmMailAccountAPI,
  paramKey: 'mail_account',
});
