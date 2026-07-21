import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import MesDashboardIndex from './pages/MesDashboardIndex.vue';
import MesProductionOrdersIndex from './pages/MesProductionOrdersIndex.vue';
import MesBomsIndex from './pages/MesBomsIndex.vue';
import MesPurchaseOrdersIndex from './pages/MesPurchaseOrdersIndex.vue';
import MesStockEntriesIndex from './pages/MesStockEntriesIndex.vue';
import MesMaterialIssuesIndex from './pages/MesMaterialIssuesIndex.vue';
import MesProductionRecordsIndex from './pages/MesProductionRecordsIndex.vue';
import MesFgInboundIndex from './pages/MesFgInboundIndex.vue';
import MesShipmentsIndex from './pages/MesShipmentsIndex.vue';
import MesStockBalancesIndex from './pages/MesStockBalancesIndex.vue';
import MesMaterialsIndex from './pages/MesMaterialsIndex.vue';
import MesSuppliersIndex from './pages/MesSuppliersIndex.vue';
import MesWarehousesIndex from './pages/MesWarehousesIndex.vue';

// MES 生产管理：与 CRM 同账号同登录；S0 全员可见（车间/仓管未必有 crm_role），
// 故 requiresCrmAccess: false，仅受 CRM 功能开关约束。
const mesMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  requiresCrmAccess: false,
};

const mesPage = (path, name, component) => {
  const meta = { ...mesMeta };
  return {
    path: frontendURL(`accounts/:accountId/mes/${path}`),
    component,
    meta,
    children: [{ path: '', name, component, meta }],
  };
};

export const routes = [
  mesPage('dashboard', 'mes_dashboard_index', MesDashboardIndex),
  mesPage('production-orders', 'mes_production_orders_index', MesProductionOrdersIndex),
  mesPage('boms', 'mes_boms_index', MesBomsIndex),
  mesPage('purchase-orders', 'mes_purchase_orders_index', MesPurchaseOrdersIndex),
  mesPage('stock-entries', 'mes_stock_entries_index', MesStockEntriesIndex),
  mesPage('material-issues', 'mes_material_issues_index', MesMaterialIssuesIndex),
  mesPage('production-records', 'mes_production_records_index', MesProductionRecordsIndex),
  mesPage('fg-inbound', 'mes_fg_inbound_index', MesFgInboundIndex),
  mesPage('shipments', 'mes_shipments_index', MesShipmentsIndex),
  mesPage('stock-balances', 'mes_stock_balances_index', MesStockBalancesIndex),
  mesPage('materials', 'mes_materials_index', MesMaterialsIndex),
  mesPage('suppliers', 'mes_suppliers_index', MesSuppliersIndex),
  mesPage('warehouses', 'mes_warehouses_index', MesWarehousesIndex),
];
