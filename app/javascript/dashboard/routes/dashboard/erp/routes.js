import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import ErpDashboardIndex from './pages/ErpDashboardIndex.vue';
import ErpPlaceholderIndex from './pages/ErpPlaceholderIndex.vue';

// ERP（财务管理）板块：与 CRM 同账号同登录；页面级前端只做展示，
// 数据权限后端把关（Erp::BaseController 403，仅管理员/副管理员/财务）。
// requiresCrmAccess: false —— 门禁交后端，避免副管理员/财务因无 crm_role 被前端误拦。
const erpMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  requiresCrmAccess: false,
};

const erpPage = (path, name, component) => {
  const meta = { ...erpMeta };
  return {
    path: frontendURL(`accounts/:accountId/erp/${path}`),
    component,
    meta,
    children: [{ path: '', name, component, meta }],
  };
};

// E0：看板已有独立页；其余板块先挂共用占位页，随各切片落地再替换为独立组件。
export const routes = [
  erpPage('dashboard', 'erp_dashboard_index', ErpDashboardIndex),
  erpPage('accounts', 'erp_accounts_index', ErpPlaceholderIndex),
  erpPage('vouchers', 'erp_vouchers_index', ErpPlaceholderIndex),
  erpPage('ledgers', 'erp_ledgers_index', ErpPlaceholderIndex),
  erpPage('reports', 'erp_reports_index', ErpPlaceholderIndex),
  erpPage('receivables', 'erp_receivables_index', ErpPlaceholderIndex),
  erpPage('payables', 'erp_payables_index', ErpPlaceholderIndex),
];
