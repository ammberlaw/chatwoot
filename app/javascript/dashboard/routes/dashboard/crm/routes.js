import { frontendURL } from '../../../helper/URLHelper';
import CrmCustomersIndex from './pages/CrmCustomersIndex.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm/customers'),
    component: CrmCustomersIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'crm_customers_index',
        component: CrmCustomersIndex,
        meta: commonMeta,
      },
    ],
  },
];
