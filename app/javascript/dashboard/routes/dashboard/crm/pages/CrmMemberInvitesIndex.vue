<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import InvitesAPI from 'dashboard/api/crm/memberInvites';
import MembersAPI from 'dashboard/api/crm/members';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { accountId } = useAccount();

const L = {
  header: '成员邀请',
  subtitle:
    '生成邀请链接发给新成员（微信/邮件均可），对方打开链接填写姓名、邮箱、密码即可按预设角色加入。',
  role: '系统角色',
  modules: '模块权限',
  department: '加入部门',
  deptNone: '不指定',
  note: '备注',
  notePlaceholder: '如：新来的业务员小王',
  expires: '有效期',
  days7: '7 天',
  days30: '30 天',
  generate: '生成邀请链接',
  copied: '邀请链接已复制，发给对方即可',
  createdNoCopy: '邀请已生成，请在下方列表点「复制链接」',
  manualCopy: '自动复制不可用，请手动复制以下链接：',
  copy: '复制链接',
  copyOk: '已复制',
  revoke: '作废',
  confirmRevoke: '确认作废',
  revoked: '邀请已作废',
  error: '操作失败',
  loading: '加载中…',
  empty: '还没有邀请记录',
  colInvite: '邀请',
  colRole: '角色 / 部门',
  colStatus: '状态',
  colExpires: '有效期至',
  statusPending: '待加入',
  statusUsed: '已加入',
  statusExpired: '已过期',
  directHeader: '直接新建成员',
  directHint:
    '不发链接：管理员直接设定账号密码，创建后立即可登录；账号密码会自动复制，发给对方即可。',
  directName: '姓名',
  directNamePlaceholder: '如：王小明',
  directEmail: '登录邮箱',
  directEmailPlaceholder: 'name@company.com',
  directPassword: '初始密码',
  directPasswordPlaceholder: '至少 8 位含大小写/数字/符号',
  genPassword: '随机',
  directCreate: '新建成员',
  directCreated: '成员已创建，账号密码已复制，发给对方即可',
  directCreatedNoCopy: '成员已创建（自动复制不可用，请手动记录账号密码）',
  directRequired: '请填写姓名、登录邮箱和初始密码',
};

const ROLE_LABELS = {
  administrator: '超级管理员',
  deputy_admin: '管理员',
  manager: '部门负责人',
  sales: '业务员',
};
// 防提权：管理员（deputy_admin）不可生成超级管理员邀请（后端同口径拦截）。
const currentUser = useMapGetter('getCurrentUser');
const ROLE_OPTIONS = computed(() =>
  Object.entries(ROLE_LABELS)
    .filter(
      ([value]) =>
        value !== 'administrator' || currentUser.value?.role === 'administrator'
    )
    .map(([value, label]) => ({ value, label }))
);
// ERP/MES 未上线：开关置灰，功能上线后去掉 disabled 即开放设置。
const MODULE_OPTIONS = [
  { key: 'crm', label: 'CRM' },
  { key: 'erp', label: 'ERP', disabled: true },
  { key: 'mes', label: 'MES', disabled: true },
];
const EXPIRES_OPTIONS = [
  { value: '7', label: L.days7 },
  { value: '30', label: L.days30 },
];

const invites = ref([]);
const departments = ref([]);
const loading = ref(true);
const creating = ref(false);
const pendingRevokeId = ref(null);
const form = ref({
  systemRole: 'sales',
  modules: ['crm', 'erp', 'mes'],
  departmentId: '',
  note: '',
  expiresDays: '7',
});

// 部门下拉按组织树顺序展开：缩进表层级，重名部门附上级名区分（如两个「设计部」）。
const departmentOptions = computed(() => {
  const byParent = {};
  departments.value.forEach(d => {
    (byParent[d.parent_id || 0] ||= []).push(d);
  });
  Object.values(byParent).forEach(arr =>
    arr.sort((a, b) => a.position - b.position)
  );
  const nameCounts = {};
  departments.value.forEach(d => {
    nameCounts[d.name] = (nameCounts[d.name] || 0) + 1;
  });
  const byId = Object.fromEntries(departments.value.map(d => [d.id, d]));
  const out = [{ value: '', label: L.deptNone }];
  const walk = (parentId, depth) => {
    (byParent[parentId || 0] || []).forEach(d => {
      const parent = byId[d.parent_id];
      const suffix =
        nameCounts[d.name] > 1 && parent ? `（${parent.name}）` : '';
      out.push({
        value: String(d.id),
        label: `${'\u00A0\u00A0'.repeat(depth)}${d.name}${suffix}`,
      });
      walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  return out;
});

const joinUrl = invite =>
  `${window.location.origin}/app/auth/join/${invite.token}`;
const statusLabel = invite =>
  ({
    pending: L.statusPending,
    used: L.statusUsed,
    expired: L.statusExpired,
  })[invite.status] || invite.status;
const fmtDateTime = v => (v ? new Date(v).toLocaleString('zh-CN') : '');

const fetchInvites = async () => {
  try {
    const { data } = await InvitesAPI.get();
    invites.value = data.payload || [];
  } catch {
    invites.value = [];
  } finally {
    loading.value = false;
  }
};

const fetchDepartments = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/org/departments`
    );
    departments.value = data.payload || [];
  } catch {
    departments.value = [];
  }
};

// HTTP 环境（生产暂无 HTTPS）没有 navigator.clipboard，退回 execCommand 复制。
const copyText = async text => {
  if (navigator.clipboard) {
    await navigator.clipboard.writeText(text);
    return;
  }
  const holder = document.createElement('textarea');
  holder.value = text;
  holder.setAttribute('readonly', '');
  holder.style.position = 'fixed';
  holder.style.opacity = '0';
  document.body.appendChild(holder);
  holder.select();
  const ok = document.execCommand('copy');
  holder.remove();
  if (!ok) throw new Error('copy unsupported');
};

const copyLink = async invite => {
  try {
    await copyText(joinUrl(invite));
    useAlert(L.copyOk);
  } catch {
    // eslint-disable-next-line no-alert
    window.prompt(L.manualCopy, joinUrl(invite));
  }
};

const createInvite = async () => {
  creating.value = true;
  try {
    const { data } = await InvitesAPI.create({
      invite: {
        system_role: form.value.systemRole,
        module_access: form.value.modules,
        department_id: form.value.departmentId || null,
        note: form.value.note.trim(),
        expires_days: form.value.expiresDays,
      },
    });
    invites.value.unshift(data);
    form.value.note = '';
    // 复制失败不算生成失败（HTTP 环境剪贴板受限时列表里仍可手动复制）。
    try {
      await copyText(joinUrl(data));
      useAlert(L.copied);
    } catch {
      useAlert(L.createdNoCopy);
    }
  } catch {
    useAlert(L.error);
  } finally {
    creating.value = false;
  }
};

// 作废两步确认；已使用的邀请留档不可删。
const revokeInvite = async invite => {
  if (pendingRevokeId.value !== invite.id) {
    pendingRevokeId.value = invite.id;
    return;
  }
  pendingRevokeId.value = null;
  try {
    await InvitesAPI.delete(invite.id);
    invites.value = invites.value.filter(i => i.id !== invite.id);
    useAlert(L.revoked);
  } catch {
    useAlert(L.error);
  }
};

const toggleModule = key => {
  const idx = form.value.modules.indexOf(key);
  if (idx >= 0) form.value.modules.splice(idx, 1);
  else form.value.modules.push(key);
};

// ---- 直接新建成员（免链接） ----
const DIRECT_FORM_DEFAULTS = {
  name: '',
  email: '',
  password: '',
  systemRole: 'sales',
  departmentId: '',
};
const directForm = ref({ ...DIRECT_FORM_DEFAULTS });
const creatingDirect = ref(false);

// 生成满足密码策略（大小写+数字+特殊字符）的 12 位随机密码。
const genPassword = () => {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghjkmnpqrstuvwxyz';
  const digits = '23456789';
  const special = '@#%!*';
  const all = upper + lower + digits + special;
  const pick = pool => pool[Math.floor(Math.random() * pool.length)];
  let password = pick(upper) + pick(lower) + pick(digits) + pick(special);
  for (let i = 0; i < 8; i += 1) password += pick(all);
  directForm.value.password = password;
};

const createDirect = async () => {
  const f = directForm.value;
  if (!f.name.trim() || !f.email.trim() || !f.password) {
    useAlert(L.directRequired);
    return;
  }
  creatingDirect.value = true;
  try {
    await MembersAPI.create({
      member: {
        name: f.name.trim(),
        email: f.email.trim(),
        password: f.password,
        system_role: f.systemRole,
        module_access: ['crm', 'erp', 'mes'],
        department_id: f.departmentId || null,
      },
    });
    const creds = `地址：${window.location.origin}\n账号：${f.email.trim()}\n密码：${f.password}`;
    directForm.value = { ...DIRECT_FORM_DEFAULTS };
    try {
      await copyText(creds);
      useAlert(L.directCreated);
    } catch {
      useAlert(L.directCreatedNoCopy);
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
  } finally {
    creatingDirect.value = false;
  }
};

onMounted(() => {
  fetchInvites();
  fetchDepartments();
});
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
      <!-- 生成邀请 -->
      <div
        class="flex flex-wrap items-end gap-4 px-6 py-4 border-b border-n-weak"
      >
        <div class="flex flex-col gap-1 w-36">
          <span class="text-xs font-medium text-n-slate-11">{{ L.role }}</span>
          <Select v-model="form.systemRole" :options="ROLE_OPTIONS" />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">
            {{ L.modules }}
          </span>
          <div class="flex items-center h-10 gap-4">
            <label
              v-for="mod in MODULE_OPTIONS"
              :key="mod.key"
              class="flex items-center gap-1.5 text-sm text-n-slate-11"
              :class="
                mod.disabled
                  ? 'opacity-50 cursor-not-allowed'
                  : 'cursor-pointer'
              "
              :title="mod.disabled ? '该模块未上线，上线后开放设置' : ''"
            >
              <input
                type="checkbox"
                class="accent-n-iris-9"
                :checked="form.modules.includes(mod.key)"
                :disabled="mod.disabled"
                @change="toggleModule(mod.key)"
              />
              {{ mod.label }}
            </label>
          </div>
        </div>
        <div class="flex flex-col gap-1 w-40">
          <span class="text-xs font-medium text-n-slate-11">
            {{ L.department }}
          </span>
          <Select v-model="form.departmentId" :options="departmentOptions" />
        </div>
        <div class="flex flex-col gap-1 w-28">
          <span class="text-xs font-medium text-n-slate-11">
            {{ L.expires }}
          </span>
          <Select v-model="form.expiresDays" :options="EXPIRES_OPTIONS" />
        </div>
        <div class="flex flex-col flex-1 min-w-48 gap-1">
          <span class="text-xs font-medium text-n-slate-11">{{ L.note }}</span>
          <Input v-model="form.note" :placeholder="L.notePlaceholder" />
        </div>
        <Button
          type="button"
          :label="L.generate"
          icon="i-lucide-link"
          color="iris"
          :is-loading="creating"
          @click="createInvite"
        />
      </div>

      <!-- 直接新建成员（免链接） -->
      <div class="px-6 py-4 border-b border-n-weak">
        <p class="text-xs font-medium text-n-slate-11">
          {{ L.directHeader }}
          <span class="ml-2 font-normal text-n-slate-10">
            {{ L.directHint }}
          </span>
        </p>
        <div class="flex flex-wrap items-end gap-4 mt-3">
          <div class="flex flex-col gap-1 w-32">
            <span class="text-xs font-medium text-n-slate-11">
              {{ L.directName }}
            </span>
            <Input
              v-model="directForm.name"
              :placeholder="L.directNamePlaceholder"
            />
          </div>
          <div class="flex flex-col gap-1 w-52">
            <span class="text-xs font-medium text-n-slate-11">
              {{ L.directEmail }}
            </span>
            <Input
              v-model="directForm.email"
              :placeholder="L.directEmailPlaceholder"
            />
          </div>
          <div class="flex flex-col gap-1 w-48">
            <span class="text-xs font-medium text-n-slate-11">
              {{ L.directPassword }}
            </span>
            <div class="flex items-center gap-1">
              <Input
                v-model="directForm.password"
                :placeholder="L.directPasswordPlaceholder"
              />
              <Button
                type="button"
                :label="L.genPassword"
                size="sm"
                variant="faded"
                color="slate"
                @click="genPassword"
              />
            </div>
          </div>
          <div class="flex flex-col gap-1 w-36">
            <span class="text-xs font-medium text-n-slate-11">
              {{ L.role }}
            </span>
            <Select v-model="directForm.systemRole" :options="ROLE_OPTIONS" />
          </div>
          <div class="flex flex-col gap-1 w-40">
            <span class="text-xs font-medium text-n-slate-11">
              {{ L.department }}
            </span>
            <Select
              v-model="directForm.departmentId"
              :options="departmentOptions"
            />
          </div>
          <Button
            type="button"
            :label="L.directCreate"
            icon="i-lucide-user-plus"
            color="iris"
            :is-loading="creatingDirect"
            @click="createDirect"
          />
        </div>
      </div>

      <!-- 邀请列表 -->
      <p v-if="loading" class="p-6 text-sm text-n-slate-10">{{ L.loading }}</p>
      <div
        v-else-if="!invites.length"
        class="flex flex-col items-center gap-2 mt-16 text-n-slate-10"
      >
        <span class="i-lucide-user-plus size-8 opacity-40" />
        <p class="text-sm">{{ L.empty }}</p>
      </div>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b border-n-weak text-n-slate-10">
            <th class="px-6 py-3 font-medium">{{ L.colInvite }}</th>
            <th class="px-6 py-3 font-medium">{{ L.colRole }}</th>
            <th class="px-6 py-3 font-medium">{{ L.colStatus }}</th>
            <th class="px-6 py-3 font-medium">{{ L.colExpires }}</th>
            <th class="px-6 py-3 font-medium w-48" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="invite in invites"
            :key="invite.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-6 py-3">
              <div class="font-medium text-n-slate-12">
                {{ invite.note || `邀请 #${invite.id}` }}
              </div>
              <div class="text-xs text-n-slate-10">
                {{ fmtDateTime(invite.created_at) }} ·
                {{ (invite.module_access || []).join(' / ').toUpperCase() }}
              </div>
            </td>
            <td class="px-6 py-3 text-n-slate-11">
              {{ ROLE_LABELS[invite.system_role] || invite.system_role }}
              <span v-if="invite.department_name" class="text-n-slate-10">
                · {{ invite.department_name }}
              </span>
            </td>
            <td class="px-6 py-3">
              <span
                class="px-2 py-0.5 rounded-full text-xs"
                :class="{
                  'bg-n-amber-3 text-n-amber-11': invite.status === 'pending',
                  'bg-n-teal-3 text-n-teal-11': invite.status === 'used',
                  'bg-n-slate-3 text-n-slate-11': invite.status === 'expired',
                }"
              >
                {{ statusLabel(invite) }}
              </span>
              <span
                v-if="invite.used_by_name"
                class="ml-1.5 text-xs text-n-slate-10"
              >
                {{ invite.used_by_name }}
              </span>
            </td>
            <td class="px-6 py-3 text-n-slate-11 tabular-nums">
              {{ fmtDateTime(invite.expires_at) }}
            </td>
            <td class="px-6 py-3">
              <div class="flex items-center justify-end gap-1.5">
                <button
                  v-if="invite.status === 'pending'"
                  type="button"
                  class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full text-n-iris-11 hover:bg-n-iris-3"
                  @click="copyLink(invite)"
                >
                  {{ L.copy }}
                </button>
                <button
                  v-if="invite.status !== 'used'"
                  type="button"
                  class="px-2.5 py-1 text-xs font-medium transition-colors rounded-full"
                  :class="
                    pendingRevokeId === invite.id
                      ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                      : 'text-n-ruby-11 hover:bg-n-ruby-3'
                  "
                  @click="revokeInvite(invite)"
                >
                  {{
                    pendingRevokeId === invite.id ? L.confirmRevoke : L.revoke
                  }}
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
