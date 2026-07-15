import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

/**
 * CRM 角色口径（与后端 Crm::AccessScope 一致）：
 * 管理员全部 / 主管(crm_role=manager)团队 / 其余按普通业务处理（仅本人数据）。
 */
export function useCrmRole() {
  const currentUser = useMapGetter('getCurrentUser');
  const isAdmin = computed(() => currentUser.value?.role === 'administrator');
  const isCrmManager = computed(
    () => currentUser.value?.crm_role === 'manager'
  );
  const isCrmSales = computed(() => !isAdmin.value && !isCrmManager.value);
  return { currentUser, isAdmin, isCrmManager, isCrmSales };
}
