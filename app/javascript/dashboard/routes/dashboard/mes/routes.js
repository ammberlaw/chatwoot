import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import MesLayout from './MesLayout.vue';
import MesDashboardIndex from './pages/MesDashboardIndex.vue';
import MesPipelineBoardIndex from './pages/MesPipelineBoardIndex.vue';
import MesProductionOrdersIndex from './pages/MesProductionOrdersIndex.vue';
import MesSupplierReturnsIndex from './pages/MesSupplierReturnsIndex.vue';
import MesProductionOrderIntakeIndex from './pages/MesProductionOrderIntakeIndex.vue';
import MesBomsIndex from './pages/MesBomsIndex.vue';
import MesBomIntakeIndex from './pages/MesBomIntakeIndex.vue';
import MesProductsIndex from './pages/MesProductsIndex.vue';
import MesMaterialPricesIndex from './pages/MesMaterialPricesIndex.vue';
import MesPurchaseOrdersIndex from './pages/MesPurchaseOrdersIndex.vue';
import MesPurchaseOrderIntakeIndex from './pages/MesPurchaseOrderIntakeIndex.vue';
import MesPurchaseRequisitionsIndex from './pages/MesPurchaseRequisitionsIndex.vue';
import MesSuppliersIndex from './pages/MesSuppliersIndex.vue';
import MesStockEntriesIndex from './pages/MesStockEntriesIndex.vue';
import MesMaterialIssuesIndex from './pages/MesMaterialIssuesIndex.vue';
import MesMaterialReturnsIndex from './pages/MesMaterialReturnsIndex.vue';
import MesProductionRecordsIndex from './pages/MesProductionRecordsIndex.vue';
import MesInspectionsIndex from './pages/MesInspectionsIndex.vue';
import MesFgInboundIndex from './pages/MesFgInboundIndex.vue';
import MesShipmentsIndex from './pages/MesShipmentsIndex.vue';
import MesNotificationsIndex from './pages/MesNotificationsIndex.vue';
import MesStockBalancesIndex from './pages/MesStockBalancesIndex.vue';
import MesStockConversionsIndex from './pages/MesStockConversionsIndex.vue';
import MesWarehousesIndex from './pages/MesWarehousesIndex.vue';
import MesSerialNumbersIndex from './pages/MesSerialNumbersIndex.vue';

// MES 生产管理：与 CRM 同账号同登录；S0 全员可见（车间/仓管未必有 crm_role），
// 故 requiresCrmAccess: false，仅受 CRM 功能开关约束。
const mesMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent'],
  requiresCrmAccess: false,
};

// 外层用 MesLayout 壳（带以产品线为 key 的 router-view）；实际页面作为其子路由渲染，
// 切换产品线时只重挂该页（重跑 onMounted 拉取），整站 MES 页按线过滤，且不刷新整个应用。
const mesPage = (path, name, component) => {
  const meta = { ...mesMeta };
  return {
    path: frontendURL(`accounts/:accountId/mes/${path}`),
    component: MesLayout,
    meta,
    children: [{ path: '', name, component, meta }],
  };
};

export const routes = [
  mesPage('dashboard', 'mes_dashboard_index', MesDashboardIndex),
  mesPage(
    'supplier-returns',
    'mes_supplier_returns_index',
    MesSupplierReturnsIndex
  ),
  mesPage('pipeline', 'mes_pipeline_index', MesPipelineBoardIndex),
  mesPage(
    'production-orders',
    'mes_production_orders_index',
    MesProductionOrdersIndex
  ),
  mesPage(
    'production-order-intake',
    'mes_production_order_intake_index',
    MesProductionOrderIntakeIndex
  ),
  mesPage('boms', 'mes_boms_index', MesBomsIndex),
  // 生产任务单建档页：新建/编辑不再用弹窗（反馈 A2——弹窗太窄，一条用料明细看不全）。
  mesPage('bom-intake', 'mes_bom_intake_index', MesBomIntakeIndex),
  mesPage('products', 'mes_products_index', MesProductsIndex),
  // 物料单价表（财务/采购维护的标准价，给成本核算兜底）
  mesPage(
    'material-prices',
    'mes_material_prices_index',
    MesMaterialPricesIndex
  ),
  mesPage(
    'purchase-orders',
    'mes_purchase_orders_index',
    MesPurchaseOrdersIndex
  ),
  // 采购单建档页：新建/编辑不再用弹窗（一个供应商几十行料，弹窗装不下）。
  mesPage(
    'purchase-order-intake',
    'mes_purchase_order_intake_index',
    MesPurchaseOrderIntakeIndex
  ),
  mesPage(
    'purchase-requisitions',
    'mes_purchase_requisitions_index',
    MesPurchaseRequisitionsIndex
  ),
  mesPage('suppliers', 'mes_suppliers_index', MesSuppliersIndex),
  mesPage('stock-entries', 'mes_stock_entries_index', MesStockEntriesIndex),
  mesPage(
    'material-issues',
    'mes_material_issues_index',
    MesMaterialIssuesIndex
  ),
  mesPage(
    'material-returns',
    'mes_material_returns_index',
    MesMaterialReturnsIndex
  ),
  mesPage(
    'production-records',
    'mes_production_records_index',
    MesProductionRecordsIndex
  ),
  mesPage('inspections', 'mes_inspections_index', MesInspectionsIndex),
  mesPage('fg-inbound', 'mes_fg_inbound_index', MesFgInboundIndex),
  mesPage('shipments', 'mes_shipments_index', MesShipmentsIndex),
  mesPage('notifications', 'mes_notifications_index', MesNotificationsIndex),
  mesPage('stock-balances', 'mes_stock_balances_index', MesStockBalancesIndex),
  mesPage(
    'stock-conversions',
    'mes_stock_conversions_index',
    MesStockConversionsIndex
  ),
  mesPage('warehouses', 'mes_warehouses_index', MesWarehousesIndex),
  mesPage('serial-numbers', 'mes_serial_numbers_index', MesSerialNumbersIndex),
];
