import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import TiktokTodayIndex from './pages/TiktokTodayIndex.vue';
import TiktokDashboardIndex from './pages/TiktokDashboardIndex.vue';
import TiktokSalesRecordsIndex from './pages/TiktokSalesRecordsIndex.vue';
import TiktokProfitIndex from './pages/TiktokProfitIndex.vue';
import TiktokExpensesIndex from './pages/TiktokExpensesIndex.vue';
import TiktokAssetsIndex from './pages/TiktokAssetsIndex.vue';
import TiktokShopSettingsIndex from './pages/TiktokShopSettingsIndex.vue';
import TiktokDepartmentsIndex from './pages/TiktokDepartmentsIndex.vue';

// TikTok 板块（店铺经营日报）：与 CRM 同账号同登录；页面级前端只做展示，
// 数据权限后端把关（仅管理员/副管理员，见 Tiktok::BaseController）。requiresCrmAccess: false，
// 门禁交给后端，避免副管理员因无 crm_role 被前端误拦。
const tiktokMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  requiresCrmAccess: false,
};

const tiktokPage = (path, name, component) => {
  const meta = { ...tiktokMeta };
  return {
    path: frontendURL(`accounts/:accountId/tiktok/${path}`),
    component,
    meta,
    children: [{ path: '', name, component, meta }],
  };
};

export const routes = [
  tiktokPage('today', 'tiktok_today_index', TiktokTodayIndex),
  tiktokPage('dashboard', 'tiktok_dashboard_index', TiktokDashboardIndex),
  tiktokPage(
    'sales-records',
    'tiktok_sales_records_index',
    TiktokSalesRecordsIndex
  ),
  tiktokPage('profit', 'tiktok_profit_index', TiktokProfitIndex),
  // 支出台账 / 固定资产登记：与利润表同门槛（部门负责人+财务/管理层），后端把关。
  tiktokPage('expenses', 'tiktok_expenses_index', TiktokExpensesIndex),
  tiktokPage('assets', 'tiktok_assets_index', TiktokAssetsIndex),
  tiktokPage(
    'shop-settings',
    'tiktok_shop_settings_index',
    TiktokShopSettingsIndex
  ),
  tiktokPage('departments', 'tiktok_departments_index', TiktokDepartmentsIndex),
];
