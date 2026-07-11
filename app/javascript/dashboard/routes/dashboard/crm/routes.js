import { frontendURL } from '../../../helper/URLHelper';
import CrmCustomersIndex from './pages/CrmCustomersIndex.vue';
import CrmOpportunitiesIndex from './pages/CrmOpportunitiesIndex.vue';
import CrmSalesOrdersIndex from './pages/CrmSalesOrdersIndex.vue';
import CrmEmailsIndex from './pages/CrmEmailsIndex.vue';
import CrmKnowledgeDocsIndex from './pages/CrmKnowledgeDocsIndex.vue';
import CrmSalesTargetsIndex from './pages/CrmSalesTargetsIndex.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
};

const crmPage = (path, name, component) => ({
  path: frontendURL(`accounts/:accountId/crm/${path}`),
  component,
  meta: commonMeta,
  children: [{ path: '', name, component, meta: commonMeta }],
});

export const routes = [
  crmPage('customers', 'crm_customers_index', CrmCustomersIndex),
  crmPage('opportunities', 'crm_opportunities_index', CrmOpportunitiesIndex),
  crmPage('sales-orders', 'crm_sales_orders_index', CrmSalesOrdersIndex),
  crmPage('emails', 'crm_emails_index', CrmEmailsIndex),
  crmPage('knowledge-docs', 'crm_knowledge_docs_index', CrmKnowledgeDocsIndex),
  crmPage('sales-targets', 'crm_sales_targets_index', CrmSalesTargetsIndex),
];
