<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import MembersAPI from 'dashboard/api/crm/members';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const L = {
  header: '成员权限',
  subtitle: '为每个成员设置系统角色；只有被赋予角色的成员才能进入 CRM。',
  colMember: '成员',
  colSystemRole: '系统角色',
  colModules: '模块使用权限',
  colScope: '数据范围',
  self: '当前账号',
  allModules: '全部模块',
  scopeAll: '全部数据',
  scopeDeputy: '全部数据（管理员）',
  scopeTeam: '本部门（含下级）',
  scopeSelf: '仅本人',
  scopeNone: '不可进入',
  saved: '已保存',
  error: '保存失败',
  loading: '加载中…',
  hint: '超级管理员拥有全部权限与全部模块；管理员数据范围与超级管理员相同，可管理公司资料但不含成员权限、回收站等账号管理；部门负责人看本部门（含下级）并可管理公司资料；业务员只看自己的，公司资料仅可浏览下载。模块开关控制成员能否使用对应业务系统（关闭 CRM 后即使有角色也无法进入）。',
};

// 业务系统模块开关（与后端 AccountUser::MODULES 对应）
const MODULE_OPTIONS = [
  { key: 'crm', label: 'CRM' },
  { key: 'erp', label: 'ERP' },
  { key: 'mes', label: 'MES' },
];

// 一个下拉管到底：管理员/副管理员/部门负责人/业务员/无。自己那行不可改（防自锁）。
const ROLE_OPTIONS = [
  { value: '', label: '无（不进入 CRM）' },
  { value: 'administrator', label: '超级管理员' },
  { value: 'deputy_admin', label: '管理员' },
  { value: 'manager', label: '部门负责人' },
  { value: 'sales', label: '业务员' },
];

const currentUserId = useMapGetter('getCurrentUserID');
const currentUser = useMapGetter('getCurrentUser');
// 防提权：管理员（deputy_admin）不可任免超级管理员——选项隐藏、超管行只读（后端同口径拦截）。
const isSuperAdmin = computed(
  () => currentUser.value?.role === 'administrator'
);
const roleOptions = computed(() =>
  isSuperAdmin.value
    ? ROLE_OPTIONS
    : ROLE_OPTIONS.filter(o => o.value !== 'administrator')
);
const members = ref([]);
const loading = ref(true);
const savingId = ref(null);

const scopeLabel = m => {
  if (m.is_admin) return L.scopeAll;
  if (m.crm_role === 'deputy_admin') return L.scopeDeputy;
  if (m.crm_role === 'manager') return L.scopeTeam;
  if (m.crm_role === 'sales') return L.scopeSelf;
  return L.scopeNone;
};
const roleValue = m => (m.is_admin ? 'administrator' : m.crm_role || '');

const fetchMembers = async () => {
  loading.value = true;
  try {
    const { data } = await MembersAPI.get();
    members.value = data.payload || [];
  } catch {
    useAlert(L.error);
  } finally {
    loading.value = false;
  }
};

const onRoleChange = async (member, value) => {
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { system_role: value || '' },
    });
    Object.assign(member, data);
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
    fetchMembers();
  } finally {
    savingId.value = null;
  }
};

const onModuleToggle = async (member, key, checked) => {
  const modules = new Set(member.module_access || []);
  if (checked) modules.add(key);
  else modules.delete(key);
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { module_access: [...modules] },
    });
    Object.assign(member, data);
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
    fetchMembers();
  } finally {
    savingId.value = null;
  }
};

onMounted(fetchMembers);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
      <p class="mt-0.5 text-xs text-n-slate-10">{{ L.subtitle }}</p>
    </div>

    <div class="flex-1 overflow-y-auto">
      <p v-if="loading" class="p-6 text-sm text-n-slate-10">{{ L.loading }}</p>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak text-n-slate-10">
            <th class="px-6 py-3 font-medium">{{ L.colMember }}</th>
            <th class="px-6 py-3 font-medium w-56">{{ L.colSystemRole }}</th>
            <th class="px-6 py-3 font-medium">{{ L.colModules }}</th>
            <th class="px-6 py-3 font-medium">{{ L.colScope }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="m in members"
            :key="m.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-3">
              <div class="flex items-center gap-3">
                <Avatar
                  :name="m.name"
                  :src="m.avatar_url || ''"
                  :size="34"
                  rounded-full
                />
                <div class="min-w-0">
                  <div class="font-medium truncate text-n-slate-12">
                    {{ m.name }}
                  </div>
                  <div class="text-xs truncate text-n-slate-10">
                    {{ m.email }}
                  </div>
                </div>
              </div>
            </td>
            <td class="px-6 py-3">
              <!-- 自己那行不可改（防自锁）；管理员对超级管理员行只读（防提权） -->
              <div
                v-if="
                  m.user_id === currentUserId || (m.is_admin && !isSuperAdmin)
                "
                class="flex items-center gap-2"
              >
                <span
                  class="px-2 py-0.5 rounded-full text-xs bg-n-iris-3 text-n-iris-11"
                >
                  {{ ROLE_OPTIONS.find(o => o.value === roleValue(m))?.label }}
                </span>
                <span
                  v-if="m.user_id === currentUserId"
                  class="text-xs text-n-slate-9"
                  >{{ L.self }}</span
                >
              </div>
              <Select
                v-else
                class="w-full"
                :model-value="roleValue(m)"
                :options="roleOptions"
                :disabled="savingId === m.id"
                @update:model-value="value => onRoleChange(m, value)"
              />
            </td>
            <td class="px-6 py-3">
              <!-- 管理员始终全模块；其他人按开关 -->
              <span v-if="m.is_admin" class="text-xs text-n-slate-10">
                {{ L.allModules }}
              </span>
              <div v-else class="flex items-center gap-4">
                <label
                  v-for="mod in MODULE_OPTIONS"
                  :key="mod.key"
                  class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
                >
                  <input
                    type="checkbox"
                    class="accent-n-iris-9"
                    :checked="(m.module_access || []).includes(mod.key)"
                    :disabled="savingId === m.id"
                    @change="e => onModuleToggle(m, mod.key, e.target.checked)"
                  />
                  {{ mod.label }}
                </label>
              </div>
            </td>
            <td class="px-6 py-3 text-n-slate-11">{{ scopeLabel(m) }}</td>
          </tr>
        </tbody>
      </table>

      <p class="px-6 py-3 text-xs text-n-slate-9">{{ L.hint }}</p>
    </div>
  </div>
</template>
