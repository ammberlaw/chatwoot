import { ref, computed } from 'vue';

/**
 * MES 板块的多标签（照金蝶那套：开过的页留在顶部标签条里，点回去就是原来的状态）。
 *
 * 状态本身是模块级单例——标签条要跨路由存活，挂在组件里会随页面卸载清空。
 * 页面状态的保留由 MesLayout 的 keep-alive 负责，这里只管“开了哪些、当前是哪个”。
 */
const MAX_TABS = 12;

// 路由名 → 标签标题的 i18n 键（与侧栏同源，保证叫法一致）。
export const MES_TAB_LABEL_KEYS = {
  mes_dashboard_index: 'SIDEBAR.MES_DASHBOARD',
  mes_pipeline_index: 'SIDEBAR.MES_PIPELINE',
  mes_notifications_index: 'SIDEBAR.MES_NOTIFICATIONS',
  mes_production_orders_index: 'SIDEBAR.MES_PRODUCTION_ORDERS',
  mes_boms_index: 'SIDEBAR.MES_BOMS',
  mes_products_index: 'SIDEBAR.MES_PRODUCTS',
  mes_purchase_requisitions_index: 'SIDEBAR.MES_PURCHASE_REQUISITIONS',
  mes_purchase_orders_index: 'SIDEBAR.MES_PURCHASE_ORDERS',
  mes_suppliers_index: 'SIDEBAR.MES_SUPPLIERS',
  mes_stock_entries_index: 'SIDEBAR.MES_STOCK_ENTRIES',
  mes_material_issues_index: 'SIDEBAR.MES_MATERIAL_ISSUES',
  mes_production_records_index: 'SIDEBAR.MES_PRODUCTION_RECORDS',
  mes_inspections_index: 'SIDEBAR.MES_INSPECTIONS',
  mes_fg_inbound_index: 'SIDEBAR.MES_FG_INBOUND',
  mes_shipments_index: 'SIDEBAR.MES_SHIPMENTS',
  mes_production_order_intake_index: 'SIDEBAR.MES_PRODUCTION_ORDERS',
};

const tabs = ref([]); // [{ name, fullPath }]
const activeName = ref('');

export function useMesTabs() {
  // 进入某个 MES 页：没开过就新开一个，开过就把它激活并更新 fullPath（带上最新的查询参数）。
  const openTab = route => {
    const name = route?.name;
    if (!name || !MES_TAB_LABEL_KEYS[name]) return;

    const existing = tabs.value.find(t => t.name === name);
    if (existing) existing.fullPath = route.fullPath;
    else {
      tabs.value.push({ name, fullPath: route.fullPath });
      // 超出上限先关最早开的（当前页永远不动）。
      if (tabs.value.length > MAX_TABS) {
        const victim = tabs.value.find(t => t.name !== name);
        if (victim) tabs.value = tabs.value.filter(t => t !== victim);
      }
    }
    activeName.value = name;
  };

  // 关标签。关的是当前页时返回相邻那个的 fullPath，让调用方跳过去；否则返回 null。
  const closeTab = name => {
    const index = tabs.value.findIndex(t => t.name === name);
    if (index === -1) return null;

    const wasActive = activeName.value === name;
    tabs.value.splice(index, 1);
    if (!wasActive) return null;

    const next = tabs.value[index] || tabs.value[index - 1];
    activeName.value = next?.name || '';
    return next?.fullPath || null;
  };

  const closeOthers = name => {
    tabs.value = tabs.value.filter(t => t.name === name);
    activeName.value = name;
  };

  return {
    tabs: computed(() => tabs.value),
    activeName: computed(() => activeName.value),
    openTab,
    closeTab,
    closeOthers,
  };
}
