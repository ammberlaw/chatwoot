import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

/**
 * CRM 角色口径（与后端 Crm::AccessScope 一致）：
 * 管理员/副管理员(crm_role=deputy_admin)全部 / 部门负责人(crm_role=manager)团队 /
 * 其余按普通业务处理（仅本人数据）。
 */
export function useCrmRole() {
  const currentUser = useMapGetter('getCurrentUser');
  const isAdmin = computed(() => currentUser.value?.role === 'administrator');
  const isCrmDeputyAdmin = computed(
    () => currentUser.value?.crm_role === 'deputy_admin'
  );
  const isCrmManager = computed(
    () => currentUser.value?.crm_role === 'manager'
  );
  const isCrmSales = computed(
    () => !isAdmin.value && !isCrmDeputyAdmin.value && !isCrmManager.value
  );
  return { currentUser, isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmSales };
}
