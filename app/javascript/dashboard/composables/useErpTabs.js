import { ref, computed } from 'vue';

/**
 * ERP 板块的多标签（与 MES 的 useMesTabs 同一套做法，见那边的注释）。
 *
 * 状态是模块级单例——标签条要跨路由存活，挂在组件里会随页面卸载清空。
 * 页面状态（填到一半的单据、筛选、滚动）由 ErpLayout 的 keep-alive 负责，
 * 这里只管「开了哪些、当前是哪个」。
 *
 * 为什么不直接复用 useMesTabs：两个板块的标签条要各记各的，混在一起会出现
 * 在 ERP 里看到 MES 的页签、点一下跳出板块（侧栏按 activeModule 切，见 ROUTE_MODULE）。
 */
const MAX_TABS = 12;

// 路由名 → 标签标题。ERP 侧栏用的就是中文字面量（不像 MES 走 i18n 键），这里保持一致，
// 两处叫法必须一样——标签条上写「凭证」侧栏写「记账凭证」会让人以为是两个地方。
export const ERP_TAB_LABELS = {
  erp_dashboard_index: '财务看板',
  erp_accounts_index: '会计科目表',
  erp_vouchers_index: '记账凭证',
  erp_ledgers_index: '账簿',
  erp_reports_index: '财务报表',
  erp_receivables_index: '应收台账',
  erp_shipment_approvals_index: '出库审核',
  erp_payables_index: '应付台账',
  erp_cash_index: '资金账户',
  erp_margin_index: '成本毛利',
  erp_bom_costs_index: 'BOM 成本表',
  erp_expenses_index: '费用报销',
  erp_fixed_assets_index: '固定资产',
  erp_periods_index: '期末结账',
  erp_notifications_index: '财务通知',
  erp_settings_index: '财务设置',
};

const tabs = ref([]); // [{ name, fullPath }]
const activeName = ref('');

export function useErpTabs() {
  // 进入某个 ERP 页：没开过就新开一个，开过就激活并更新 fullPath（带上最新查询参数）。
  const openTab = route => {
    const name = route?.name;
    if (!name || !ERP_TAB_LABELS[name]) return;

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

  const moveTab = (fromName, toName) => {
    if (!fromName || fromName === toName) return;

    const from = tabs.value.findIndex(t => t.name === fromName);
    const to = tabs.value.findIndex(t => t.name === toName);
    if (from === -1 || to === -1) return;

    const [moved] = tabs.value.splice(from, 1);
    tabs.value.splice(to, 0, moved);
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
    moveTab,
  };
}
