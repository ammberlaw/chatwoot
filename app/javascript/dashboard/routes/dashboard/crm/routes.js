import { frontendURL } from '../../../helper/URLHelper';
import CrmCustomersIndex from './pages/CrmCustomersIndex.vue';
import CrmOpportunitiesIndex from './pages/CrmOpportunitiesIndex.vue';
import CrmOpportunityFunnelIndex from './pages/CrmOpportunityFunnelIndex.vue';
import CrmSalesOrdersIndex from './pages/CrmSalesOrdersIndex.vue';
import CrmEmailsIndex from './pages/CrmEmailsIndex.vue';
import CrmKnowledgeDocsIndex from './pages/CrmKnowledgeDocsIndex.vue';
import CrmSalesTargetsIndex from './pages/CrmSalesTargetsIndex.vue';
import CrmMailAccountsIndex from './pages/CrmMailAccountsIndex.vue';
import CrmEmailTemplatesIndex from './pages/CrmEmailTemplatesIndex.vue';
import CrmDashboardIndex from './pages/CrmDashboardIndex.vue';
import CrmTeamDashboardIndex from './pages/CrmTeamDashboardIndex.vue';
import CrmMyTargetIndex from './pages/CrmMyTargetIndex.vue';
import CrmCustomerOnboardingIndex from './pages/CrmCustomerOnboardingIndex.vue';
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

// A-CRM routes
export const routes = [
  crmPage('dashboard', 'crm_dashboard_index', CrmDashboardIndex),
  crmPage('team-dashboard', 'crm_team_dashboard_index', CrmTeamDashboardIndex),
  crmPage('my-target', 'crm_my_target_index', CrmMyTargetIndex),
  crmPage('customer-intake', 'crm_customer_intake_index', CrmCustomerOnboardingIndex),
  crmPage('customers', 'crm_customers_index', CrmCustomersIndex),
  crmPage('opportunities', 'crm_opportunities_index', CrmOpportunitiesIndex),
  crmPage('funnel', 'crm_funnel_index', CrmOpportunityFunnelIndex),
  crmPage('sales-orders', 'crm_sales_orders_index', CrmSalesOrdersIndex),
  crmPage('emails', 'crm_emails_index', CrmEmailsIndex),
  crmPage('knowledge-docs', 'crm_knowledge_docs_index', CrmKnowledgeDocsIndex),
  crmPage('sales-targets', 'crm_sales_targets_index', CrmSalesTargetsIndex),
  crmPage('mail-accounts', 'crm_mail_accounts_index', CrmMailAccountsIndex),
  crmPage('email-templates', 'crm_email_templates_index', CrmEmailTemplatesIndex),
];
