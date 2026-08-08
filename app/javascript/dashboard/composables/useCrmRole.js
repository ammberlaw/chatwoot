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
  // 有效主管身份用后端派生的 crm_manager（覆盖副管理员/管理员兼任部门负责人）；
  // 兜底再看 crm_role，避免旧缓存的 currentUser 缺字段。
  const isCrmManager = computed(
    () =>
      currentUser.value?.crm_manager === true ||
      currentUser.value?.crm_role === 'manager'
  );
  // CRM 团队负责人（crm_teams.team_lead_id）——独立于部门主管，销售订单按 CRM 团队放行「全部」视图用。
  const isCrmTeamLead = computed(
    () => currentUser.value?.crm_team_lead === true
  );
  const isCrmHr = computed(() => currentUser.value?.crm_role === 'hr');
  // 财务身份（与业务员身份叠加）：可查看全员「已通过」提成表并导出。管理员天然具备。
  const isCrmFinance = computed(
    () => isAdmin.value || currentUser.value?.crm_finance === true
  );
  const isCrmSales = computed(
    () => !isAdmin.value && !isCrmDeputyAdmin.value && !isCrmManager.value
  );
  return {
    currentUser,
    isAdmin,
    isCrmDeputyAdmin,
    isCrmManager,
    isCrmTeamLead,
    isCrmHr,
    isCrmFinance,
    isCrmSales,
  };
}
