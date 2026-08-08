import { frontendURL } from '../../../helper/URLHelper';
import CrmLayout from './CrmLayout.vue';
import CrmCustomersIndex from './pages/CrmCustomersIndex.vue';
import CrmCustomerDupesIndex from './pages/CrmCustomerDupesIndex.vue';
import CrmAiBackgroundCheckIndex from './pages/CrmAiBackgroundCheckIndex.vue';
import CrmOpportunitiesIndex from './pages/CrmOpportunitiesIndex.vue';
import CrmOpportunityFunnelIndex from './pages/CrmOpportunityFunnelIndex.vue';
import CrmSalesOrdersIndex from './pages/CrmSalesOrdersIndex.vue';
import CrmPisIndex from './pages/CrmPisIndex.vue';
import CrmCommissionSheetsIndex from './pages/CrmCommissionSheetsIndex.vue';
import CrmCommissionSheetDetailIndex from './pages/CrmCommissionSheetDetailIndex.vue';
import CrmEmailsIndex from './pages/CrmEmailsIndex.vue';
import CrmKnowledgeDocsIndex from './pages/CrmKnowledgeDocsIndex.vue';
import CrmSalesTargetsIndex from './pages/CrmSalesTargetsIndex.vue';
import CrmMailAccountsIndex from './pages/CrmMailAccountsIndex.vue';
import CrmEmailTemplatesIndex from './pages/CrmEmailTemplatesIndex.vue';
import CrmAiSettingsIndex from './pages/CrmAiSettingsIndex.vue';
import CrmOrgStructureIndex from './pages/CrmOrgStructureIndex.vue';
import CrmOrgChartIndex from './pages/CrmOrgChartIndex.vue';
import CrmTeamsIndex from './pages/CrmTeamsIndex.vue';
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
import CrmCustomerSettingsIndex from './pages/CrmCustomerSettingsIndex.vue';
import CrmCustomerDetailIndex from './pages/CrmCustomerDetailIndex.vue';
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
const crmPages = [
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
  crmPage('customers/:id', 'crm_customer_detail_index', CrmCustomerDetailIndex),
  crmPage('customer-dupes', 'crm_customer_dupes_index', CrmCustomerDupesIndex),
  crmPage(
    'ai-background-check',
    'crm_ai_background_check_index',
    CrmAiBackgroundCheckIndex
  ),
  crmPage(
    'public-pool-settings',
    'crm_public_pool_settings_index',
    CrmPublicPoolSettingsIndex
  ),
  crmPage(
    'customer-settings',
    'crm_customer_settings_index',
    CrmCustomerSettingsIndex
  ),
  crmPage('opportunities', 'crm_opportunities_index', CrmOpportunitiesIndex),
  crmPage('funnel', 'crm_funnel_index', CrmOpportunityFunnelIndex),
  crmPage('pis', 'crm_pis_index', CrmPisIndex),
  crmPage('sales-orders', 'crm_sales_orders_index', CrmSalesOrdersIndex),
  // 提成表在「人事绩效」组，与 KPI 考核表一样走 SHARED（不加 requiresCrmAccess 守卫，
  // 避免 store 里 can_access_crm 缓存缺失时被弹到 crm/workspace）；数据权限由后端 ensure_crm_access 把关。
  crmPage(
    'commission-sheets',
    'crm_commission_sheets_index',
    CrmCommissionSheetsIndex,
    SHARED
  ),
  crmPage(
    'commission-sheets/detail',
    'crm_commission_sheet_detail',
    CrmCommissionSheetDetailIndex,
    SHARED
  ),
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
  crmPage('ai-settings', 'crm_ai_settings_index', CrmAiSettingsIndex),
  crmPage(
    'org-structure',
    'crm_org_structure_index',
    CrmOrgStructureIndex,
    SHARED
  ),
  crmPage('org-chart', 'crm_org_chart_index', CrmOrgChartIndex, SHARED),
  // CRM 团队管理：写操作后端限超管/管理员；主管/业务员只读可见自己团队。
  crmPage('teams', 'crm_teams_index', CrmTeamsIndex),
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
  // 成员权限管理：超管/管理员/人事/部门负责人（后端 ensure_admin 把关）；人事无 CRM 数据权限，故走 SHARED 不受 CRM 门禁。
  crmPage('members', 'crm_members_index', CrmMembersIndex, SHARED),
  // 成员邀请：生成加入链接（超管/管理员/人事）；人事无 CRM 数据权限，故走 SHARED 不受 CRM 门禁。
  crmPage(
    'member-invites',
    'crm_member_invites_index',
    CrmMemberInvitesIndex,
    SHARED
  ),
];

// 用 CrmLayout 包住所有 CRM 页 → 写信窗挂在这层，CRM 各模块间切换不卸载、常驻不消失。
// 子路由沿用各自绝对路径，父层只提供常驻布局壳（不改变 URL 与路由名）。
export const routes = [
  {
    path: frontendURL('accounts/:accountId/crm'),
    component: CrmLayout,
    children: crmPages,
  },
];
