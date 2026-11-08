import { frontendURL } from '../../../helper/URLHelper';
import CrmLayout from './CrmLayout.vue';
import CrmCustomersIndex from './pages/CrmCustomersIndex.vue';
import CrmCustomerDupesIndex from './pages/CrmCustomerDupesIndex.vue';
import CrmAiBackgroundCheckIndex from './pages/CrmAiBackgroundCheckIndex.vue';
import CrmBusinessCardsIndex from './pages/CrmBusinessCardsIndex.vue';
import CrmExhibitionsIndex from './pages/CrmExhibitionsIndex.vue';
import CrmOpportunitiesIndex from './pages/CrmOpportunitiesIndex.vue';
import CrmOpportunityFunnelIndex from './pages/CrmOpportunityFunnelIndex.vue';
import CrmSalesOrdersIndex from './pages/CrmSalesOrdersIndex.vue';
import CrmPisIndex from './pages/CrmPisIndex.vue';
import CrmQuotesIndex from './pages/CrmQuotesIndex.vue';
import CrmQuoteRequestsIndex from './pages/CrmQuoteRequestsIndex.vue';
import CrmQuoteRequestTemplatesIndex from './pages/CrmQuoteRequestTemplatesIndex.vue';
import CrmPriceListsIndex from './pages/CrmPriceListsIndex.vue';
import CrmCommissionSheetsIndex from './pages/CrmCommissionSheetsIndex.vue';
import CrmCommissionSheetDetailIndex from './pages/CrmCommissionSheetDetailIndex.vue';
import CrmEmailsIndex from './pages/CrmEmailsIndex.vue';
import CrmKnowledgeDocsIndex from './pages/CrmKnowledgeDocsIndex.vue';
import CrmSalesTargetsIndex from './pages/CrmSalesTargetsIndex.vue';
import CrmMailAccountsIndex from './pages/CrmMailAccountsIndex.vue';
import CrmLeadCenterIndex from './pages/CrmLeadCenterIndex.vue';
import CrmEmailTemplatesIndex from './pages/CrmEmailTemplatesIndex.vue';
import CrmAiSettingsIndex from './pages/CrmAiSettingsIndex.vue';
import CrmAgentIndex from './pages/CrmAgentIndex.vue';
import CrmInboxCollaboratorsIndex from './pages/CrmInboxCollaboratorsIndex.vue';
import CrmOrgStructureIndex from './pages/CrmOrgStructureIndex.vue';
import CrmOrgChartIndex from './pages/CrmOrgChartIndex.vue';
import CrmTeamsIndex from './pages/CrmTeamsIndex.vue';
import CrmApprovalsIndex from './pages/CrmApprovalsIndex.vue';
import CrmPettyCashIndex from './pages/CrmPettyCashIndex.vue';
import CrmPiBackfillIndex from './pages/CrmPiBackfillIndex.vue';
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
import CrmDashboardSettingsIndex from './pages/CrmDashboardSettingsIndex.vue';
import CrmIssueReportsIndex from './pages/CrmIssueReportsIndex.vue';
import CrmCustomerDetailIndex from './pages/CrmCustomerDetailIndex.vue';
import CrmEmployeeCompsIndex from './pages/CrmEmployeeCompsIndex.vue';
import CrmPayrollSheetsIndex from './pages/CrmPayrollSheetsIndex.vue';
import CrmPayrollSheetDetailIndex from './pages/CrmPayrollSheetDetailIndex.vue';
import CrmEmployeesIndex from './pages/CrmEmployeesIndex.vue';
import CrmAttendanceIndex from './pages/CrmAttendanceIndex.vue';
import CrmScheduleIndex from './pages/CrmScheduleIndex.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  // 默认 CRM 数据页需 CRM 权限；共享模块（工作台/OA/HR/协同/文档中心）单独覆盖为 false。
  requiresCrmAccess: true,
};

// 全员可用的共享模块（非 CRM 销售数据），不受 CRM 门禁限制。
const SHARED = { requiresCrmAccess: false };

// 仍需 CRM 门禁，但对「纯财务」额外放行（对账要看单，写操作后端挡着）。
const FINANCE_READABLE = { allowCrmFinance: true };

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
  crmPage('schedule', 'crm_schedule_index', CrmScheduleIndex, SHARED),
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
  crmPage(
    'business-cards',
    'crm_business_cards_index',
    CrmBusinessCardsIndex
  ),
  crmPage('exhibitions', 'crm_exhibitions_index', CrmExhibitionsIndex),
  crmPage('opportunities', 'crm_opportunities_index', CrmOpportunitiesIndex),
  crmPage('funnel', 'crm_funnel_index', CrmOpportunityFunnelIndex),
  crmPage('price-lists', 'crm_price_lists_index', CrmPriceListsIndex),
  crmPage('quotes', 'crm_quotes_index', CrmQuotesIndex),
  crmPage('quote-requests', 'crm_quote_requests_index', CrmQuoteRequestsIndex),
  crmPage(
    'quote-request-templates',
    'crm_quote_request_templates_index',
    CrmQuoteRequestTemplatesIndex
  ),
  // 纯财务只读放行这两页（后端 ensure_crm_or_finance! + block_crm_finance_writes! 把关）。
  crmPage('pis', 'crm_pis_index', CrmPisIndex, FINANCE_READABLE),
  crmPage(
    'sales-orders',
    'crm_sales_orders_index',
    CrmSalesOrdersIndex,
    FINANCE_READABLE
  ),
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
  // 新客开发：主动拓客（AI 客户画像 + 本地化关键词 → 搜潜在买家）
  crmPage('lead-center', 'crm_lead_center_index', CrmLeadCenterIndex),
  crmPage('mail-accounts', 'crm_mail_accounts_index', CrmMailAccountsIndex),
  crmPage(
    'email-templates',
    'crm_email_templates_index',
    CrmEmailTemplatesIndex
  ),
  crmPage('ai-settings', 'crm_ai_settings_index', CrmAiSettingsIndex),
  // CRM AI 助手（带工具的 agent，见 Crm::Agent::Runner）
  crmPage('agent', 'crm_agent_index', CrmAgentIndex),
  crmPage(
    'inbox-collaborators',
    'crm_inbox_collaborators_index',
    CrmInboxCollaboratorsIndex
  ),
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
  // 工资表：财务/人事核算。门禁走后端 policy（管理层 + 财务 + 人事）＋二次验证。
  crmPage('payroll', 'crm_payroll_sheets_index', CrmPayrollSheetsIndex, SHARED),
  // 看板设置：目前管「谁计入成交排行」。归在 CRM 设置分组下。
  crmPage('dashboard-settings', 'crm_dashboard_settings_index', CrmDashboardSettingsIndex),
  // 业务员在 AI 助手里报上来的问题单（超管/副管，后端 ensure_admin 把关）。
  crmPage(
    'issue-reports',
    'crm_issue_reports_index',
    CrmIssueReportsIndex,
    SHARED
  ),
  crmPage(
    'payroll/detail',
    'crm_payroll_sheet_detail',
    CrmPayrollSheetDetailIndex,
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
  // 备用金台账：财务/管理员记账，部门负责人看本部门；走 SHARED 不受 CRM 数据门禁（财务常无 crm_role）。
  crmPage('petty-cash', 'crm_petty_cash_index', CrmPettyCashIndex, SHARED),
  // 历史 PI 补录：把早期传在客户「文件」页的 PI 补建成销售订单（一次性工具）。
  crmPage('pi-backfill', 'crm_pi_backfill_index', CrmPiBackfillIndex),
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
