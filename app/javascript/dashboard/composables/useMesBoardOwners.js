import { ref } from 'vue';
import MesBoardOwnersAPI from 'dashboard/api/mes/boardOwners';
import CrmMemberAPI from 'dashboard/api/crm/members';

// 模块级缓存：负责人表跨 MES 各页只拉一次；成员名单仅管理员设置时按需拉取。
const ownersByKey = ref({}); // board_key -> { managerIds, managerNames }
const members = ref([]);
let ownersLoaded = false;
let ownersPromise = null;
let membersLoaded = false;
let membersPromise = null;

const applyOwner = o => {
  ownersByKey.value = {
    ...ownersByKey.value,
    [o.board_key]: {
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
        map[o.board_key] = {
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

const saveOwners = async (boardKey, managerIds) => {
  const { data } = await MesBoardOwnersAPI.set({
    board_key: boardKey,
    manager_ids: managerIds,
  });
  applyOwner(data);
};

export function useMesBoardOwners() {
  return { ownersByKey, members, loadOwners, ensureMembers, saveOwners };
}
