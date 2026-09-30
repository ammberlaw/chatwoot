import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// 单据「谁制单谁改」：非制单人不能改也不能删，审批人只能批不能改，系统管理员可代改。
// 口径必须和后端 Mes::BaseController#ensure_owner_or_admin! 完全一致——
// 后端只放行 administrator（不含副管理员），前端跟着放宽就会出现「按钮点了吃 403」。
// 前端只管按钮显隐，真正的拦截在后端。
export function useMesDocOwner() {
  const currentUserId = useMapGetter('getCurrentUserID');
  const currentRole = useMapGetter('getCurrentRole');
  const isSystemAdmin = computed(() => currentRole.value === 'administrator');

  // 制单人为空的老单不拦（判定不了是谁建的），与后端同样处理。
  const isMyDoc = (doc, attr = 'ownerId') =>
    isSystemAdmin.value || !doc?.[attr] || doc[attr] === currentUserId.value;

  return { isMyDoc, isSystemAdmin };
}
