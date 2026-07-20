import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from '../../../featureFlags';
import MesProductionOrdersIndex from './pages/MesProductionOrdersIndex.vue';
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
  mesPage('production-orders', 'mes_production_orders_index', MesProductionOrdersIndex),
  mesPage('materials', 'mes_materials_index', MesMaterialsIndex),
  mesPage('suppliers', 'mes_suppliers_index', MesSuppliersIndex),
  mesPage('warehouses', 'mes_warehouses_index', MesWarehousesIndex),
];
