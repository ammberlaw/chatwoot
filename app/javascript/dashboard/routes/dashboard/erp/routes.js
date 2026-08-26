import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import ErpDashboardIndex from './pages/ErpDashboardIndex.vue';
import ErpAccountsIndex from './pages/ErpAccountsIndex.vue';
import ErpVouchersIndex from './pages/ErpVouchersIndex.vue';
import ErpLedgersIndex from './pages/ErpLedgersIndex.vue';
import ErpReportsIndex from './pages/ErpReportsIndex.vue';
import ErpReceivablesIndex from './pages/ErpReceivablesIndex.vue';
import ErpPayablesIndex from './pages/ErpPayablesIndex.vue';
import ErpCashIndex from './pages/ErpCashIndex.vue';
import ErpPeriodsIndex from './pages/ErpPeriodsIndex.vue';
import ErpFixedAssetsIndex from './pages/ErpFixedAssetsIndex.vue';
import ErpMarginIndex from './pages/ErpMarginIndex.vue';

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

// ERP 各板块均已有独立页面（E0 的共用占位页已下线）。
export const routes = [
  erpPage('dashboard', 'erp_dashboard_index', ErpDashboardIndex),
  erpPage('accounts', 'erp_accounts_index', ErpAccountsIndex),
  erpPage('vouchers', 'erp_vouchers_index', ErpVouchersIndex),
  erpPage('ledgers', 'erp_ledgers_index', ErpLedgersIndex),
  erpPage('reports', 'erp_reports_index', ErpReportsIndex),
  erpPage('receivables', 'erp_receivables_index', ErpReceivablesIndex),
  erpPage('payables', 'erp_payables_index', ErpPayablesIndex),
  erpPage('cash', 'erp_cash_index', ErpCashIndex),
  erpPage('periods', 'erp_periods_index', ErpPeriodsIndex),
  erpPage('fixed-assets', 'erp_fixed_assets_index', ErpFixedAssetsIndex),
  erpPage('margin', 'erp_margin_index', ErpMarginIndex),
];
