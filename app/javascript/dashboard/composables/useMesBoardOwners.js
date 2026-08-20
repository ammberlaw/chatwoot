import { ref } from 'vue';
import MesBoardOwnersAPI from 'dashboard/api/mes/boardOwners';
import CrmMemberAPI from 'dashboard/api/crm/members';

// 模块级缓存：负责人表跨 MES 各页只拉一次；成员名单仅管理员设置时按需拉取。
// 阶段负责人按产品线分：缓存键 = `${board_key}::${product_line}`（product_line ''=全部产线）。
const ownersByKey = ref({}); // `${board_key}::${line}` -> { managerIds, managerNames }
const members = ref([]);
let ownersLoaded = false;
let ownersPromise = null;
let membersLoaded = false;
let membersPromise = null;

// 复合键：阶段 + 产品线（空线归 '' 全部产线）。
export const boardOwnerKey = (boardKey, line) => `${boardKey}::${line || ''}`;

const applyOwner = o => {
  ownersByKey.value = {
    ...ownersByKey.value,
    [boardOwnerKey(o.board_key, o.product_line)]: {
      managerIds: o.manager_ids || [],
      managerNames: o.manager_names || [],
    },
  };
};

const loadOwners = () => {
  if (ownersLoaded) return Promise.resolve();
  if (ownersPromise) return ownersPromise;
  ownersPromise = MesBoardOwnersAPI.get()
    .then(({ data }) => {
      const map = {};
      (data?.payload || []).forEach(o => {
        map[boardOwnerKey(o.board_key, o.product_line)] = {
          managerIds: o.manager_ids || [],
          managerNames: o.manager_names || [],
        };
      });
      ownersByKey.value = map;
      ownersLoaded = true;
    })
    .catch(() => {})
    .finally(() => {
      ownersPromise = null;
    });
  return ownersPromise;
};

const ensureMembers = () => {
  if (membersLoaded) return Promise.resolve();
  if (membersPromise) return membersPromise;
  membersPromise = CrmMemberAPI.get()
    .then(({ data }) => {
      members.value = data?.payload || [];
      membersLoaded = true;
    })
    .catch(() => {})
    .finally(() => {
      membersPromise = null;
    });
  return membersPromise;
};

const saveOwners = async (boardKey, managerIds, productLine = '') => {
  const { data } = await MesBoardOwnersAPI.set({
    board_key: boardKey,
    product_line: productLine,
    manager_ids: managerIds,
  });
  applyOwner(data);
};

export function useMesBoardOwners() {
  return { ownersByKey, members, loadOwners, ensureMembers, saveOwners };
}
