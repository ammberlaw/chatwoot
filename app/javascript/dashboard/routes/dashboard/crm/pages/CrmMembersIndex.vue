<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import MembersAPI from 'dashboard/api/crm/members';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const L = {
  header: 'CRM 成员权限',
  subtitle: '只有被赋予 CRM 角色的成员才能进入 CRM。系统管理员自动拥有全部权限。',
  colMember: '成员',
  colSystemRole: '系统角色',
  colCrmRole: 'CRM 角色',
  colScope: '数据范围',
  admin: '管理员',
  agent: '普通成员',
  adminFull: '管理员（全权）',
  scopeAll: '全部数据',
  scopeTeam: '本团队',
  scopeSelf: '仅本人',
  scopeNone: '不可进入',
  saved: '已保存',
  error: '保存失败',
  loading: '加载中…',
  hint: '主管看本团队的客户与商机，业务员只看自己的。',
};

// 空串=清除（无 CRM 权限）。管理员行不可改。
const ROLE_OPTIONS = [
  { value: '', label: '无（不进入 CRM）' },
  { value: 'manager', label: '主管' },
  { value: 'sales', label: '业务员' },
];

const members = ref([]);
const loading = ref(true);
const savingId = ref(null);

const scopeLabel = m => {
  if (m.is_admin) return L.scopeAll;
  if (m.crm_role === 'manager') return L.scopeTeam;
  if (m.crm_role === 'sales') return L.scopeSelf;
  return L.scopeNone;
};

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
      member: { crm_role: value || '' },
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
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
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
            <th class="px-6 py-3 font-medium">{{ L.colSystemRole }}</th>
            <th class="px-6 py-3 font-medium w-56">{{ L.colCrmRole }}</th>
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
              <span
                class="px-2 py-0.5 rounded-full text-xs"
                :class="
                  m.is_admin
                    ? 'bg-n-amber-3 text-n-amber-11'
                    : 'bg-n-slate-3 text-n-slate-11'
                "
              >
                {{ m.is_admin ? L.admin : L.agent }}
              </span>
            </td>
            <td class="px-6 py-3">
              <span v-if="m.is_admin" class="text-xs text-n-slate-10">
                {{ L.adminFull }}
              </span>
              <Select
                v-else
                class="w-full"
                :model-value="m.crm_role || ''"
                :options="ROLE_OPTIONS"
                :disabled="savingId === m.id"
                @update:model-value="value => onRoleChange(m, value)"
              />
            </td>
            <td class="px-6 py-3 text-n-slate-11">{{ scopeLabel(m) }}</td>
          </tr>
        </tbody>
      </table>

      <p class="px-6 py-3 text-xs text-n-slate-9">{{ L.hint }}</p>
    </div>
  </div>
</template>
