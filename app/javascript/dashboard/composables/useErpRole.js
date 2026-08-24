import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// ERP（财务管理）写权限：读 currentUser.erp_capabilities（后端按 erp_role 下发的能力域数组）。
// 能力域：receivable / payable / payment / cash / cost / ledger / voucher / report / close / asset / doc / claim / supplier。
// 管理员/副管理员后端已给全部能力。后端 Erp::BaseController 以 403 兜底，前端仅控按钮显隐。
export function useErpRole() {
  const currentUser = useMapGetter('getCurrentUser');
  const capabilities = computed(() => currentUser.value?.erp_capabilities || []);
  const canAccessErp = computed(
    () => currentUser.value?.can_access_erp === true
  );
  const erpCan = domain => capabilities.value.includes(domain);
  return { capabilities, canAccessErp, erpCan };
}
