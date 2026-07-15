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
import CrmOrgStructureIndex from './pages/CrmOrgStructureIndex.vue';
import CrmApprovalsIndex from './pages/CrmApprovalsIndex.vue';
import CrmApprovalTemplatesIndex from './pages/CrmApprovalTemplatesIndex.vue';
import CrmTeamChatIndex from './pages/CrmTeamChatIndex.vue';
import CrmWorkspaceHome from './pages/CrmWorkspaceHome.vue';
import CrmDashboardIndex from './pages/CrmDashboardIndex.vue';
import CrmTeamDashboardIndex from './pages/CrmTeamDashboardIndex.vue';
import CrmMyTargetIndex from './pages/CrmMyTargetIndex.vue';
import CrmMembersIndex from './pages/CrmMembersIndex.vue';
import CrmMemberInvitesIndex from './pages/CrmMemberInvitesIndex.vue';
import CrmCustomerOnboardingIndex from './pages/CrmCustomerOnboardingIndex.vue';
import CrmKpiSchemesIndex from './pages/CrmKpiSchemesIndex.vue';
import CrmKpiSchemeEditorIndex from './pages/CrmKpiSchemeEditorIndex.vue';
import CrmKpiSheetsIndex from './pages/CrmKpiSheetsIndex.vue';
import CrmKpiSheetDetailIndex from './pages/CrmKpiSheetDetailIndex.vue';
import CrmPerformanceSettingsIndex from './pages/CrmPerformanceSettingsIndex.vue';
import CrmPublicPoolSettingsIndex from './pages/CrmPublicPoolSettingsIndex.vue';
import CrmEmployeeCompsIndex from './pages/CrmEmployeeCompsIndex.vue';
import CrmEmployeesIndex from './pages/CrmEmployeesIndex.vue';
import CrmAttendanceIndex from './pages/CrmAttendanceIndex.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  // 默认 CRM 数据页需 CRM 权限；共享模块（工作台/OA/HR/协同/文档中心）单独覆盖为 false。
  requiresCrmAccess: true,
};

// 全员可用的共享模块（非 CRM 销售数据），不受 CRM 门禁限制。
const SHARED = { requiresCrmAccess: false };

const crmPage = (path, name, component, extraMeta = {}) => {
  const meta = { ...commonMeta, ...extraMeta };
  return {
    path: frontendURL(`accounts/:accountId/crm/${path}`),
    component,
    meta,
    children: [{ path: '', name, component, meta }],
  };
};

// Wintouch-CRM routes
export const routes = [
  crmPage('workspace', 'crm_workspace_index', CrmWorkspaceHome, SHARED),
  crmPage('dashboard', 'crm_dashboard_index', CrmDashboardIndex),
  crmPage('team-dashboard', 'crm_team_dashboard_index', CrmTeamDashboardIndex),
  crmPage('my-target', 'crm_my_target_index', CrmMyTargetIndex),
  crmPage(
    'customer-intake',
    'crm_customer_intake_index',
    CrmCustomerOnboardingIndex
  ),
  crmPage('customers', 'crm_customers_index', CrmCustomersIndex),
  crmPage(
    'public-pool-settings',
    'crm_public_pool_settings_index',
    CrmPublicPoolSettingsIndex
  ),
  crmPage('opportunities', 'crm_opportunities_index', CrmOpportunitiesIndex),
  crmPage('funnel', 'crm_funnel_index', CrmOpportunityFunnelIndex),
  crmPage('sales-orders', 'crm_sales_orders_index', CrmSalesOrdersIndex),
  crmPage('emails', 'crm_emails_index', CrmEmailsIndex),
  crmPage('knowledge-docs', 'crm_knowledge_docs_index', CrmKnowledgeDocsIndex, {
    library: 'SALES',
  }),
  crmPage('doc-center', 'crm_doc_center_index', CrmKnowledgeDocsIndex, {
    library: 'GENERAL',
    ...SHARED,
  }),
  crmPage('sales-targets', 'crm_sales_targets_index', CrmSalesTargetsIndex),
  crmPage('mail-accounts', 'crm_mail_accounts_index', CrmMailAccountsIndex),
  crmPage(
    'email-templates',
    'crm_email_templates_index',
    CrmEmailTemplatesIndex
  ),
  crmPage(
    'org-structure',
    'crm_org_structure_index',
    CrmOrgStructureIndex,
    SHARED
  ),
  crmPage('kpi-schemes', 'crm_kpi_schemes_index', CrmKpiSchemesIndex, SHARED),
  crmPage(
    'kpi-schemes/edit',
    'crm_kpi_scheme_editor',
    CrmKpiSchemeEditorIndex,
    SHARED
  ),
  crmPage('kpi-sheets', 'crm_kpi_sheets_index', CrmKpiSheetsIndex, SHARED),
  crmPage(
    'kpi-sheets/detail',
    'crm_kpi_sheet_detail',
    CrmKpiSheetDetailIndex,
    SHARED
  ),
  crmPage(
    'performance-settings',
    'crm_performance_settings_index',
    CrmPerformanceSettingsIndex,
    SHARED
  ),
  crmPage(
    'employee-comps',
    'crm_employee_comps_index',
    CrmEmployeeCompsIndex,
    SHARED
  ),
  // 员工档案（员工主数据）：含身份证/薪酬等敏感信息，仅管理员。
  crmPage('employees', 'crm_employees_index', CrmEmployeesIndex, SHARED),
  // 考勤：打卡/月历全员可用；汇总与规则在页内按角色显隐。
  crmPage('attendance', 'crm_attendance_index', CrmAttendanceIndex, SHARED),
  crmPage('approvals', 'crm_approvals_index', CrmApprovalsIndex, SHARED),
  crmPage(
    'approval-templates',
    'crm_approval_templates_index',
    CrmApprovalTemplatesIndex,
    SHARED
  ),
  crmPage('team-chat', 'crm_team_chat_index', CrmTeamChatIndex, SHARED),
  // 成员权限管理：仅管理员（覆盖 permissions）；管理员本就有 CRM 访问权。
  crmPage('members', 'crm_members_index', CrmMembersIndex),
  // 成员邀请：生成加入链接（仅管理员）。
  crmPage('member-invites', 'crm_member_invites_index', CrmMemberInvitesIndex),
];
