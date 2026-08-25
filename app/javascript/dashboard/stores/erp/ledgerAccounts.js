import ErpLedgerAccountAPI from 'dashboard/api/erp/ledgerAccounts';
import { buildCrmStore } from 'dashboard/stores/crm/_crmStoreFactory';

export const useErpLedgerAccountsStore = buildCrmStore({
  name: 'erpLedgerAccounts',
  API: ErpLedgerAccountAPI,
  paramKey: 'ledger_account',
});
