import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// MES 写权限：读 currentUser.mes_capabilities（后端按角色下发的能力域数组）。
// 能力域：order / bom / purchase / stock / report / shipment / master。
// 管理员/副管理员后端已给全部能力。后端 policy 仍以 403 兜底，前端仅控按钮显隐。
export function useMesRole() {
  const currentUser = useMapGetter('getCurrentUser');
  const capabilities = computed(() => currentUser.value?.mes_capabilities || []);
  const mesCan = domain => capabilities.value.includes(domain);
  return { capabilities, mesCan };
}
