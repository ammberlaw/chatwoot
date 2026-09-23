import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

/**
 * 「纯财务」：有 crm_finance 标记、但没有 crm_role，因此过不了 CRM 总门禁。
 *
 * 这类人（财务）只被放行销售订单与 PI 两页，且是只读的——后端
 * ensure_crm_or_finance! + block_crm_finance_writes! 把关，前端据此隐藏写操作按钮，
 * 免得点了才报 403。
 *
 * 判定散在侧栏/门户/订单页/PI 页四处，抽这里统一，避免日后各自改走样。
 */
export function useCrmFinanceOnly() {
  const currentUser = useMapGetter('getCurrentUser');

  const isCrmFinanceOnly = computed(
    () =>
      currentUser.value?.can_access_crm === false &&
      currentUser.value?.crm_finance === true
  );

  return { isCrmFinanceOnly };
}
