<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import MembersAPI from 'dashboard/api/crm/members';
import OrgDepartmentAPI from 'dashboard/api/org/departments';
import OrgMembershipAPI from 'dashboard/api/org/memberships';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const L = {
  header: '成员权限',
  subtitle: '为每个成员设置系统角色；只有被赋予角色的成员才能进入 CRM。',
  managerSubtitle:
    '部门负责人视图：仅显示你所辖部门（含下级）的成员，可为其重置密码。',
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
};

// 底部「权限说明」折叠区：把原来一堵灰字口径拆成逐行对照，末尾一条补充说明。
const ROLE_LEGEND = [
  { role: '超级管理员', desc: '一切权限' },
  { role: '管理员', desc: '一切，除了任免 / 修改超级管理员' },
  {
    role: '部门负责人',
    desc: '本部门的一切：数据、考核打分、下属密码、考勤汇总',
  },
  { role: '业务员', desc: '只管自己' },
  { role: '无角色', desc: '仅共享模块（文档 / 审批 / 沟通 / 考勤）' },
];
const LEGEND_NOTE =
  '人事部门成员额外可维护组织架构、审批模板并自改密码。财务身份可与业务员身份叠加，用于查看全员已通过提成表并导出。模块开关控制能否使用对应业务系统（关闭 CRM 后即使有角色也无法进入）。';

// 业务系统模块开关（与后端 AccountUser::MODULES 对应）
// ERP/MES 未上线：开关置灰，功能上线后去掉 disabled 即开放设置。
const MODULE_OPTIONS = [
  { key: 'crm', label: 'CRM' },
  { key: 'erp', label: 'ERP', disabled: true },
  { key: 'mes', label: 'MES', disabled: true },
];

// 一个下拉管到底：管理员/副管理员/部门负责人/业务员/无。自己那行不可改（防自锁）。
const ROLE_OPTIONS = [
  { value: '', label: '无（不进入 CRM）' },
  { value: 'administrator', label: '超级管理员' },
  { value: 'deputy_admin', label: '管理员' },
  { value: 'manager', label: '部门负责人' },
  { value: 'sales', label: '业务员' },
  { value: 'hr', label: '人事' },
];

const currentUserId = useMapGetter('getCurrentUserID');
const currentUser = useMapGetter('getCurrentUser');

// 防提权：管理员（deputy_admin）不可任免超级管理员——选项隐藏、超管行只读（后端同口径拦截）。
const isSuperAdmin = computed(
  () => currentUser.value?.role === 'administrator'
);
const isHrActor = computed(() => currentUser.value?.crm_role === 'hr');
const roleOptions = computed(() => {
  if (isSuperAdmin.value) return ROLE_OPTIONS;
  if (isHrActor.value)
    return ROLE_OPTIONS.filter(
      o => !['administrator', 'deputy_admin'].includes(o.value)
    );
  return ROLE_OPTIONS.filter(o => o.value !== 'administrator');
});
// 部门负责人模式：后端只返回下属；页面只读展示角色/模块，仅提供重置密码。
const isManagerOnly = computed(
  () => !isSuperAdmin.value && currentUser.value?.crm_role === 'manager'
);
// 停用/恢复仅超管与管理员可操作。
const isAdminLike = computed(
  () => isSuperAdmin.value || currentUser.value?.crm_role === 'deputy_admin'
);
const isDeactivated = m => !!m.deactivated_at;
// 可否对该成员执行停用：管理层操作、非自己、且目标不是超管/管理员。
const canDeactivate = m =>
  isAdminLike.value &&
  m.user_id !== currentUserId.value &&
  !m.is_admin &&
  m.crm_role !== 'deputy_admin';
const members = ref([]);
const loading = ref(true);
const savingId = ref(null);

// 主从式：左侧列表选中谁，右侧就展示谁的权限
const selectedId = ref(null);
const selectedMember = computed(
  () => members.value.find(m => m.id === selectedId.value) || null
);
const showHint = ref(false);

const scopeLabel = m => {
  if (m.is_admin) return L.scopeAll;
  if (m.crm_role === 'deputy_admin') return L.scopeDeputy;
  if (m.crm_role === 'manager') return L.scopeTeam;
  if (m.crm_role === 'sales') return L.scopeSelf;
  return L.scopeNone;
};
const roleValue = m => (m.is_admin ? 'administrator' : m.crm_role || '');

// 系统角色只读的三种情况：自己那行（防自锁）、管理员看超管行、部门负责人视图全只读
const isRoleReadonly = m =>
  m.user_id === currentUserId.value ||
  (m.is_admin && !isSuperAdmin.value) ||
  isManagerOnly.value;

// 左栏检索 + 角色筛选（~50 人规模下快速定位）
const searchQuery = ref('');
const roleFilter = ref('all');
const ROLE_FILTERS = [
  { key: 'all', label: '全部' },
  { key: 'sales', label: '业务员' },
  { key: 'manager', label: '负责人' },
  { key: 'admin', label: '管理员' },
  { key: 'hr', label: '人事' },
  { key: 'finance', label: '财务' },
  { key: 'none', label: '无角色' },
  { key: 'deactivated', label: '已停用' },
];
const matchRoleFilter = m => {
  const v = roleValue(m);
  switch (roleFilter.value) {
    case 'sales':
      return v === 'sales';
    case 'manager':
      return v === 'manager';
    case 'admin':
      return v === 'administrator' || v === 'deputy_admin';
    case 'hr':
      return v === 'hr';
    case 'finance':
      // 财务是叠加身份（crm_finance 布尔），非系统角色；管理员天然具备
      return !!m.crm_finance;
    case 'none':
      return v === '';
    case 'deactivated':
      return isDeactivated(m);
    default:
      return true;
  }
};
const filteredMembers = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  return members.value.filter(m => {
    if (!matchRoleFilter(m)) return false;
    if (!q) return true;
    return [m.name, m.email, m.crm_name].some(s =>
      (s || '').toLowerCase().includes(q)
    );
  });
});

// 组织架构：左栏成员列表按部门分组（复用系统已有「组织架构」的部门+归属）。
const departments = ref([]);
const memberships = ref([]);
const collapsedDepts = reactive({});
const fetchOrg = async () => {
  try {
    const [dept, mem] = await Promise.all([
      OrgDepartmentAPI.get(),
      OrgMembershipAPI.get(),
    ]);
    departments.value = dept.data?.payload || [];
    memberships.value = mem.data?.payload || [];
  } catch {
    departments.value = [];
    memberships.value = [];
  }
};

// 部门按组织架构树 DFS 展平（保留层级 depth 做缩进），同级按 position 排。
const orderedDepts = computed(() => {
  const byParent = {};
  departments.value.forEach(d => {
    (byParent[d.parent_id || 0] ||= []).push(d);
  });
  Object.values(byParent).forEach(arr =>
    arr.sort((a, b) => a.position - b.position || a.id - b.id)
  );
  const out = [];
  const walk = (pid, depth) => {
    (byParent[pid] || []).forEach(d => {
      out.push({ id: d.id, name: d.name, depth });
      walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  return out;
});

// 用户 → 归属部门 id：优先 is_primary，其次首个归属；无归属归 0（未分配）。
const userDeptMap = computed(() => {
  const map = {};
  memberships.value.forEach(m => {
    if (m.is_primary) map[m.user_id] = m.department_id;
  });
  memberships.value.forEach(m => {
    if (map[m.user_id] == null) map[m.user_id] = m.department_id;
  });
  return map;
});

// 检索/筛选进行中时强制展开，方便看到命中结果。
const isFiltering = computed(
  () => !!searchQuery.value.trim() || roleFilter.value !== 'all'
);
const isDeptCollapsed = g => !isFiltering.value && !!collapsedDepts[g.id];
const toggleCollapse = id => {
  collapsedDepts[id] = !collapsedDepts[id];
};

// 左栏成员按部门分组：{ id, name, depth, members[] }，未分配部门排最后。
const memberGroups = computed(() => {
  const byDept = {};
  filteredMembers.value.forEach(m => {
    (byDept[userDeptMap.value[m.user_id] ?? 0] ||= []).push(m);
  });
  const list = orderedDepts.value
    .filter(d => byDept[d.id]?.length)
    .map(d => ({ ...d, members: byDept[d.id] }));
  if (byDept[0]?.length) {
    list.push({ id: 0, name: '未分配部门', depth: 0, members: byDept[0] });
  }
  return list;
});

const fetchMembers = async () => {
  loading.value = true;
  try {
    const { data } = await MembersAPI.get();
    members.value = data.payload || [];
    if (!members.value.some(m => m.id === selectedId.value)) {
      selectedId.value = members.value[0]?.id ?? null;
    }
  } catch {
    useAlert(L.error);
  } finally {
    loading.value = false;
  }
};

// ── 修改成员账号（姓名/邮箱/重置密码）：超管可改所有人，管理员不可改超管 ──
const accountDialog = ref(null);
const editTarget = ref(null);
const savingAccount = ref(false);
const editForm = reactive({ name: '', crm_name: '', email: '', password: '' });
const openAccountEdit = m => {
  editTarget.value = m;
  editForm.name = m.name || '';
  editForm.crm_name = m.crm_name || '';
  editForm.email = m.email || '';
  editForm.password = '';
  accountDialog.value?.open();
};
const saveAccount = async () => {
  if (savingAccount.value || !editTarget.value) return;
  savingAccount.value = true;
  try {
    const payload = isManagerOnly.value
      ? { password: editForm.password }
      : {
          name: editForm.name.trim(),
          crm_name: editForm.crm_name.trim(),
          email: editForm.email.trim(),
        };
    if (!isManagerOnly.value && editForm.password)
      payload.password = editForm.password;
    await MembersAPI.update(editTarget.value.id, { member: payload });
    accountDialog.value?.close();
    useAlert(L.saved);
    fetchMembers();
  } catch (e) {
    useAlert(e.response?.data?.error || L.error);
  } finally {
    savingAccount.value = false;
  }
};

// ── 停用（离职）/ 恢复 ──
const deactivateDialog = ref(null);
const deactivateTarget = ref(null);
const handoverMode = ref('pool');
const handoverTargetId = ref('');
const deactivating = ref(false);

// 接手人候选：在职、非本人、且能进入 CRM（可持有客户）。
const handoverTargetOptions = computed(() => {
  const opts = members.value
    .filter(
      m =>
        !isDeactivated(m) &&
        m.user_id !== deactivateTarget.value?.user_id &&
        m.can_access_crm
    )
    .map(m => ({ value: String(m.user_id), label: m.crm_name || m.name }));
  return [{ value: '', label: '选择接手人' }, ...opts];
});

const openDeactivate = m => {
  deactivateTarget.value = m;
  handoverMode.value = 'pool';
  handoverTargetId.value = '';
  deactivateDialog.value?.open();
};

const doDeactivate = async () => {
  if (deactivating.value || !deactivateTarget.value) return;
  if (handoverMode.value === 'transfer' && !handoverTargetId.value) {
    useAlert('请选择接手人');
    return;
  }
  deactivating.value = true;
  try {
    const { data } = await MembersAPI.deactivate(deactivateTarget.value.id, {
      handover_mode: handoverMode.value,
      handover_target_id:
        handoverMode.value === 'transfer' ? handoverTargetId.value : null,
    });
    Object.assign(deactivateTarget.value, data);
    deactivateDialog.value?.close();
    useAlert('已停用，该账号已退出并禁止登录');
    fetchMembers();
  } catch (e) {
    useAlert(e.response?.data?.error || L.error);
  } finally {
    deactivating.value = false;
  }
};

const doReactivate = async m => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `恢复「${m.name}」的账号？恢复后可再次登录，需重新分配角色。`
    )
  )
    return;
  savingId.value = m.id;
  try {
    const { data } = await MembersAPI.reactivate(m.id);
    Object.assign(m, data);
    useAlert('已恢复');
  } catch (e) {
    useAlert(e.response?.data?.error || L.error);
    fetchMembers();
  } finally {
    savingId.value = null;
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

const MES_ROLE_OPTIONS = [
  { value: '', label: '无(只读)' },
  { value: 'pmc', label: 'PMC 计划' },
  { value: 'engineer', label: '工程' },
  { value: 'buyer', label: '采购' },
  { value: 'warehouse', label: '仓管' },
  { value: 'production', label: '生产' },
];
const onMesRoleChange = async (member, value) => {
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { mes_role: value || '' },
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

// 财务身份：可查看全员「已通过」提成表并导出（与业务员身份叠加）。
const onFinanceToggle = async (member, checked) => {
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { crm_finance: checked },
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

onMounted(() => {
  fetchMembers();
  fetchOrg();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex-shrink-0 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
      <p class="mt-0.5 text-xs text-n-slate-10">
        {{ isManagerOnly ? L.managerSubtitle : L.subtitle }}
      </p>
    </div>

    <p v-if="loading" class="p-6 text-sm text-n-slate-10">{{ L.loading }}</p>

    <!-- 两栏主从式：左列表选人，右面板设权限（手机上下堆叠） -->
    <div v-else class="flex flex-col md:flex-row flex-1 min-h-0">
      <!-- 左：搜索 + 角色筛选 + 成员列表 -->
      <div
        class="flex flex-col flex-shrink-0 border-b md:border-b-0 md:border-r w-full md:w-60 max-h-56 md:max-h-none border-n-weak"
      >
        <div
          class="flex flex-col flex-shrink-0 gap-2 p-2 border-b border-n-weak/60"
        >
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索姓名 / 英文名 / 邮箱…"
            class="h-8 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
          />
          <div class="flex flex-wrap gap-1">
            <button
              v-for="rf in ROLE_FILTERS"
              :key="rf.key"
              class="px-2 py-0.5 text-xs rounded-full transition-colors"
              :class="
                roleFilter === rf.key
                  ? 'bg-n-iris-9 text-white'
                  : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
              "
              @click="roleFilter = rf.key"
            >
              {{ rf.label }}
            </button>
          </div>
        </div>
        <div class="flex-1 overflow-y-auto">
          <div v-for="g in memberGroups" :key="g.id">
            <!-- 部门头：折叠 + 人数 -->
            <button
              class="sticky top-0 z-10 flex items-center w-full gap-1.5 px-3 py-1.5 text-xs font-medium border-b bg-n-alpha-1 backdrop-blur text-n-slate-11 border-n-weak/60"
              :style="{ paddingLeft: `${12 + g.depth * 14}px` }"
              @click="toggleCollapse(g.id)"
            >
              <span
                class="size-3.5 text-n-slate-10"
                :class="
                  isDeptCollapsed(g)
                    ? 'i-lucide-chevron-right'
                    : 'i-lucide-chevron-down'
                "
              />
              <span class="truncate">{{ g.name }}</span>
              <span class="ml-auto text-n-slate-9">{{ g.members.length }}</span>
            </button>
            <!-- 部门成员 -->
            <template v-if="!isDeptCollapsed(g)">
              <button
                v-for="m in g.members"
                :key="m.id"
                class="flex items-center w-full gap-3 px-4 py-2.5 text-left border-b border-n-weak/60 hover:bg-n-alpha-1"
                :class="m.id === selectedId ? 'bg-n-iris-3/50' : ''"
                @click="selectedId = m.id"
              >
                <Avatar
                  :name="m.name"
                  :src="m.avatar_url || ''"
                  :size="32"
                  rounded-full
                />
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-n-slate-12">
                    {{ m.name }}
                  </div>
                  <div class="text-xs truncate text-n-slate-10">
                    <template v-if="isDeactivated(m)">
                      <span class="text-n-ruby-11">已停用</span>
                    </template>
                    <template v-else>
                      <span>{{
                        ROLE_OPTIONS.find(o => o.value === roleValue(m))?.label
                      }}</span>
                      <span v-if="m.crm_finance" class="text-n-iris-11">
                        · 财务
                      </span>
                    </template>
                  </div>
                </div>
              </button>
            </template>
          </div>
          <p
            v-if="!filteredMembers.length"
            class="px-4 py-6 text-xs text-center text-n-slate-9"
          >
            无匹配成员
          </p>
        </div>
      </div>

      <!-- 右：选中成员的权限面板 -->
      <div
        v-if="selectedMember"
        :key="selectedMember.id"
        class="flex-1 min-w-0 overflow-y-auto"
      >
        <div
          class="flex items-center gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
        >
          <Avatar
            :name="selectedMember.name"
            :src="selectedMember.avatar_url || ''"
            :size="40"
            rounded-full
          />
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ selectedMember.name }}
              </span>
              <span
                v-if="isDeactivated(selectedMember)"
                class="flex-shrink-0 px-2 py-0.5 rounded-full text-xs bg-n-ruby-3 text-n-ruby-11"
              >
                已停用
              </span>
            </div>
            <div class="text-xs truncate text-n-slate-10">
              {{ selectedMember.email }}
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-5 px-4 py-4 sm:px-6 sm:py-5 max-w-xl">
          <!-- 系统角色 -->
          <div class="flex items-center gap-4">
            <span class="flex-shrink-0 text-sm w-24 text-n-slate-11">
              {{ L.colSystemRole }}
            </span>
            <!-- 自己那行不可改（防自锁）；管理员对超管行只读；部门负责人全只读 -->
            <div
              v-if="isRoleReadonly(selectedMember)"
              class="flex items-center gap-2"
            >
              <span
                class="px-2 py-0.5 rounded-full text-xs bg-n-iris-3 text-n-iris-11"
              >
                {{
                  ROLE_OPTIONS.find(o => o.value === roleValue(selectedMember))
                    ?.label
                }}
              </span>
              <span
                v-if="selectedMember.user_id === currentUserId"
                class="text-xs text-n-slate-9"
                >{{ L.self }}</span
              >
            </div>
            <Select
              v-else
              class="flex-1"
              :model-value="roleValue(selectedMember)"
              :options="roleOptions"
              :disabled="savingId === selectedMember.id"
              @update:model-value="value => onRoleChange(selectedMember, value)"
            />
          </div>

          <!-- MES 角色 -->
          <div class="flex items-center gap-4">
            <span class="flex-shrink-0 text-sm w-24 text-n-slate-11">
              MES 角色
            </span>
            <span
              v-if="selectedMember.is_admin"
              class="text-sm text-n-slate-10"
            >
              全部
            </span>
            <Select
              v-else
              class="flex-1"
              :model-value="selectedMember.mes_role || ''"
              :options="MES_ROLE_OPTIONS"
              :disabled="savingId === selectedMember.id"
              @update:model-value="
                value => onMesRoleChange(selectedMember, value)
              "
            />
          </div>

          <!-- 财务身份：可查看全员已通过提成表 + 导出，与业务员身份叠加。管理员天然具备。 -->
          <div class="flex items-center gap-4">
            <span class="flex-shrink-0 text-sm w-24 text-n-slate-11">
              财务身份
            </span>
            <span
              v-if="selectedMember.is_admin"
              class="text-sm text-n-slate-10"
            >
              默认具备
            </span>
            <label
              v-else
              class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
            >
              <input
                type="checkbox"
                class="accent-n-iris-9"
                :checked="selectedMember.crm_finance"
                :disabled="savingId === selectedMember.id || isManagerOnly"
                @change="e => onFinanceToggle(selectedMember, e.target.checked)"
              />
              可查看全员已通过提成表并导出
            </label>
          </div>

          <!-- 模块使用权限 -->
          <div class="flex items-start gap-4">
            <span class="flex-shrink-0 pt-0.5 text-sm w-24 text-n-slate-11">
              {{ L.colModules }}
            </span>
            <!-- 管理员始终全模块；其他人按开关 -->
            <span
              v-if="selectedMember.is_admin"
              class="text-sm text-n-slate-10"
            >
              {{ L.allModules }}
            </span>
            <div v-else class="flex flex-wrap items-center gap-4">
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
                  :checked="
                    (selectedMember.module_access || []).includes(mod.key)
                  "
                  :disabled="
                    savingId === selectedMember.id ||
                    mod.disabled ||
                    isManagerOnly
                  "
                  @change="
                    e =>
                      onModuleToggle(selectedMember, mod.key, e.target.checked)
                  "
                />
                {{ mod.label }}
              </label>
            </div>
          </div>

          <!-- 数据范围 -->
          <div class="flex items-center gap-4">
            <span class="flex-shrink-0 text-sm w-24 text-n-slate-11">
              {{ L.colScope }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ scopeLabel(selectedMember) }}
            </span>
          </div>

          <!-- 操作：自己也可改中文名/CRM英文名；管理员不可动超管账号 -->
          <div
            v-if="isSuperAdmin || !selectedMember.is_admin"
            class="flex flex-wrap items-center gap-3 pt-1"
          >
            <span class="flex-shrink-0 w-24" />
            <button
              class="h-9 px-4 text-sm font-medium border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
              @click="openAccountEdit(selectedMember)"
            >
              {{ isManagerOnly ? '重置密码' : '修改账号' }}
            </button>
            <button
              v-if="isDeactivated(selectedMember) && isAdminLike"
              class="h-9 px-4 text-sm font-medium border rounded-lg border-n-grass-7 text-n-grass-11 hover:bg-n-grass-3"
              :disabled="savingId === selectedMember.id"
              @click="doReactivate(selectedMember)"
            >
              恢复账号
            </button>
            <button
              v-else-if="canDeactivate(selectedMember)"
              class="h-9 px-4 text-sm font-medium border rounded-lg border-n-ruby-7 text-n-ruby-11 hover:bg-n-ruby-3"
              @click="openDeactivate(selectedMember)"
            >
              停用 / 离职
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- 权限说明：原来一堵灰字，折成可展开的逐行对照 -->
    <div v-if="!loading" class="flex-shrink-0 border-t border-n-weak">
      <button
        class="flex items-center gap-1.5 w-full px-4 sm:px-6 py-2.5 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-1"
        @click="showHint = !showHint"
      >
        <span>权限说明</span>
        <span class="text-n-slate-9">{{ showHint ? '▾' : '▸' }}</span>
      </button>
      <div v-if="showHint" class="px-4 sm:px-6 pb-4">
        <div class="flex flex-col gap-1.5 max-w-2xl">
          <div
            v-for="item in ROLE_LEGEND"
            :key="item.role"
            class="flex gap-3 text-xs"
          >
            <span class="flex-shrink-0 w-20 font-medium text-n-slate-11">
              {{ item.role }}
            </span>
            <span class="text-n-slate-10">{{ item.desc }}</span>
          </div>
          <p class="mt-1.5 text-xs text-n-slate-9">{{ LEGEND_NOTE }}</p>
        </div>
      </div>
    </div>

    <!-- 修改成员账号弹窗 -->
    <Dialog
      ref="accountDialog"
      :title="`${isManagerOnly ? '重置密码' : '修改账号'}${editTarget ? ` · ${editTarget.name}` : ''}`"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-4">
        <label v-if="!isManagerOnly" class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">姓名（中文）</span>
          <input
            v-model="editForm.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label v-if="!isManagerOnly" class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            CRM 英文名（留空则用中文名）
          </span>
          <input
            v-model="editForm.crm_name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 Ken Chen — CRM 界面与对外邮件发件人显示"
          />
        </label>
        <label v-if="!isManagerOnly" class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">登录邮箱</span>
          <input
            v-model="editForm.email"
            type="email"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            {{ isManagerOnly ? '新密码' : '重置密码（留空则不修改）' }}
          </span>
          <input
            v-model="editForm.password"
            type="password"
            autocomplete="new-password"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="至少 8 位，含大小写字母、数字和特殊字符"
          />
        </label>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="
              savingAccount ||
              (isManagerOnly
                ? !editForm.password
                : !editForm.name.trim() || !editForm.email.trim())
            "
            @click="saveAccount"
          >
            {{ savingAccount ? '保存中…' : '保存' }}
          </button>
        </div>
      </div>
    </Dialog>

    <!-- 停用（离职）弹窗：选交接方式后一键停用 -->
    <Dialog
      ref="deactivateDialog"
      :title="`停用 / 离职${deactivateTarget ? ` · ${deactivateTarget.name}` : ''}`"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-4">
        <p class="text-xs leading-relaxed text-n-slate-11">
          停用后该账号将
          <span class="font-medium text-n-ruby-11">立即退出并禁止登录</span
          >，CRM 角色置无，个人文档进回收站。名下客户 /
          商机按下面方式交接。误操作可在此页「恢复账号」。
        </p>

        <div class="flex flex-col gap-2">
          <span class="text-xs text-n-slate-11">名下客户 / 商机交接</span>
          <label
            class="flex items-start gap-2 p-2.5 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
            :class="
              handoverMode === 'pool' ? 'border-n-iris-8 bg-n-iris-2' : ''
            "
          >
            <input
              v-model="handoverMode"
              type="radio"
              value="pool"
              class="mt-0.5 accent-n-iris-9"
            />
            <span class="text-sm text-n-slate-12">
              退回公海
              <span class="block text-xs text-n-slate-10">
                客户回到公海池，其他业务员可认领。
              </span>
            </span>
          </label>
          <label
            class="flex items-start gap-2 p-2.5 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
            :class="
              handoverMode === 'transfer' ? 'border-n-iris-8 bg-n-iris-2' : ''
            "
          >
            <input
              v-model="handoverMode"
              type="radio"
              value="transfer"
              class="mt-0.5 accent-n-iris-9"
            />
            <span class="flex-1 text-sm text-n-slate-12">
              转交给接手人
              <span class="block mb-2 text-xs text-n-slate-10">
                客户 / 商机整体转到指定业务员名下。
              </span>
              <Select
                v-if="handoverMode === 'transfer'"
                :model-value="handoverTargetId"
                :options="handoverTargetOptions"
                @update:model-value="v => (handoverTargetId = v)"
              />
            </span>
          </label>
        </div>

        <div class="flex justify-end gap-2">
          <button
            type="button"
            class="h-9 px-4 text-sm font-medium border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="deactivateDialog?.close()"
          >
            取消
          </button>
          <button
            type="button"
            class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-ruby-9 hover:bg-n-ruby-10 disabled:opacity-50"
            :disabled="deactivating"
            @click="doDeactivate"
          >
            {{ deactivating ? '处理中…' : '确认停用' }}
          </button>
        </div>
      </div>
    </Dialog>
  </div>
</template>
