<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import { useOrgDepartmentsStore } from 'dashboard/stores/org/departments';
import { useOrgMembershipsStore } from 'dashboard/stores/org/memberships';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');
// 超级管理员/管理员/人事部成员可维护组织架构（org_maintainer 由后端按部门归属判定）。
const canManage = computed(
  () =>
    isAdmin.value ||
    currentUser.value?.crm_role === 'deputy_admin' ||
    currentUser.value?.org_maintainer === true
);
const deptStore = useOrgDepartmentsStore();
const memberStore = useOrgMembershipsStore();

const L = {
  header: '组织架构',
  hint: '维护公司部门树与成员归属；后续 CRM/审批/ERP 按部门授权都以此为准。',
  addRoot: '新建部门',
  addChild: '添加子部门',
  rename: '重命名',
  move: '移动到其他部门',
  moveTitle: '移动部门',
  moveTargetLabel: '新的上级部门',
  moveTop: '— 设为顶级部门 —',
  remove: '删除',
  emptyTree: '还没有部门，点「新建部门」开始',
  namePrompt: '部门名称',
  renamePrompt: '新的部门名称',
  deleteConfirm: '删除该部门及其所有子部门、成员归属？',
  selectHint: '选择左侧部门查看/管理成员',
  leader: '负责人',
  noLeader: '未设置',
  members: '成员',
  addMember: '添加成员',
  editMember: '编辑成员',
  removeMemberConfirm: '将该成员移出此部门？',
  emptyMembers: '该部门还没有成员',
  primary: '归属部门',
  titleLabel: '职位',
  memberLabel: '成员',
  saved: '已保存',
  error: '操作失败',
  readonly: '仅超级管理员/管理员/人事部可维护组织架构（当前为只读）',
};

const departments = computed(() => deptStore.getRecords);
const isFetching = computed(() => deptStore.getUIFlags.fetchingList);

// 折叠状态：首次加载默认折叠第二层及更深的有子级节点（只展开到中心一级）。
const collapsedIds = ref(new Set());
const collapseInitialized = ref(false);

const byParentMap = computed(() => {
  const byParent = {};
  departments.value.forEach(d => {
    const key = d.parentId || 0;
    (byParent[key] ||= []).push(d);
  });
  Object.values(byParent).forEach(arr =>
    arr.sort((a, b) => a.position - b.position)
  );
  return byParent;
});

watch(byParentMap, byParent => {
  if (collapseInitialized.value || !departments.value.length) return;
  collapseInitialized.value = true;
  const collapsed = new Set();
  const walk = (parentId, depth) => {
    (byParent[parentId || 0] || []).forEach(d => {
      if (depth >= 1 && byParent[d.id]?.length) collapsed.add(d.id);
      walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  collapsedIds.value = collapsed;
});

const toggleCollapse = node => {
  const next = new Set(collapsedIds.value);
  if (next.has(node.id)) next.delete(node.id);
  else next.add(node.id);
  collapsedIds.value = next;
};

// 人员节点（总经理/副总/董事长/总裁等岗位挂在树里）：用人形图标而非部门图标。
const isPersonNode = node => /总经理|副总|董事长|总裁/.test(node.name);

// 由扁平部门（parent_id + position）构建带层级深度的有序列表，跳过已折叠子树。
const tree = computed(() => {
  const byParent = byParentMap.value;
  const out = [];
  const walk = (parentId, depth) => {
    (byParent[parentId || 0] || []).forEach(d => {
      out.push({ ...d, depth, hasChildren: Boolean(byParent[d.id]?.length) });
      if (!collapsedIds.value.has(d.id)) walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  return out;
});

const selectedDeptId = ref(null);
const selectedDept = computed(
  () => departments.value.find(d => d.id === selectedDeptId.value) || null
);
const members = computed(() => memberStore.getRecords);

const agents = ref([]);
const leaderOptions = computed(() => [
  { value: '', label: L.noLeader },
  ...members.value.map(m => ({ value: String(m.userId), label: m.userName })),
]);
const assignableAgents = computed(() => {
  const taken = new Set(members.value.map(m => m.userId));
  return agents.value.filter(a => !taken.has(a.id));
});

const fetchDepartments = () => deptStore.get();
const fetchMembers = () => {
  if (selectedDeptId.value)
    memberStore.get({ department_id: selectedDeptId.value });
};

const selectDept = dept => {
  selectedDeptId.value = dept.id;
  fetchMembers();
};

// ---- 部门增删改 ----
const addRoot = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(L.namePrompt);
  if (!name?.trim()) return;
  await deptStore.create({ name: name.trim() });
  useAlert(L.saved);
};

const addChild = async dept => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(L.namePrompt);
  if (!name?.trim()) return;
  await deptStore.create({ name: name.trim(), parentId: dept.id });
  // 父节点折叠时新子部门会被整个跳过不渲染（看起来像没加上），自动展开让它立刻可见。
  if (collapsedIds.value.has(dept.id)) {
    const next = new Set(collapsedIds.value);
    next.delete(dept.id);
    collapsedIds.value = next;
  }
  useAlert(L.saved);
};

const renameDept = async dept => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(L.renamePrompt, dept.name);
  if (!name?.trim() || name.trim() === dept.name) return;
  await deptStore.update({ id: dept.id, name: name.trim() });
  useAlert(L.saved);
};

const deleteDept = async dept => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.deleteConfirm)) return;
  await deptStore.delete(dept.id);
  if (selectedDeptId.value === dept.id) selectedDeptId.value = null;
  useAlert(L.saved);
};

// ---- 移动部门（更换上级，任意层级）----
const moveDialogRef = ref(null);
const movingDept = ref(null);
const moveTargetId = ref('');

// 目标上级选项：排除自己与全部子孙（防环，后端同样校验）；缩进体现层级。
const moveTargetOptions = computed(() => {
  if (!movingDept.value) return [];
  const excluded = new Set([movingDept.value.id]);
  const collectDescendants = id => {
    (byParentMap.value[id] || []).forEach(c => {
      excluded.add(c.id);
      collectDescendants(c.id);
    });
  };
  collectDescendants(movingDept.value.id);
  const out = [{ value: '', label: L.moveTop }];
  const walk = (parentId, depth) => {
    (byParentMap.value[parentId || 0] || []).forEach(d => {
      if (excluded.has(d.id)) return;
      out.push({
        value: String(d.id),
        label: `${'　'.repeat(depth)}${d.name}`,
      });
      walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  return out;
});

const moveDept = dept => {
  movingDept.value = dept;
  moveTargetId.value = dept.parentId ? String(dept.parentId) : '';
  moveDialogRef.value?.open();
};

const confirmMove = async () => {
  const dept = movingDept.value;
  if (!dept) return;
  const parentId = moveTargetId.value ? Number(moveTargetId.value) : null;
  if ((dept.parentId || null) === parentId) {
    moveDialogRef.value?.close();
    return;
  }
  await deptStore.update({ id: dept.id, parentId });
  // 展开新上级，让移动结果立刻可见。
  if (parentId && collapsedIds.value.has(parentId)) {
    const next = new Set(collapsedIds.value);
    next.delete(parentId);
    collapsedIds.value = next;
  }
  moveDialogRef.value?.close();
  useAlert(L.saved);
};

const setLeader = async value => {
  await deptStore.update({
    id: selectedDept.value.id,
    leaderId: value ? Number(value) : null,
  });
  useAlert(L.saved);
};

// ---- 成员管理 ----
const dialogRef = ref(null);
const editingId = ref(null);
const memberForm = ref({ userId: '', title: '', isPrimary: false });

const openAddMember = () => {
  editingId.value = null;
  memberForm.value = { userId: '', title: '', isPrimary: false };
  dialogRef.value?.open();
};

const openEditMember = m => {
  editingId.value = m.id;
  memberForm.value = {
    userId: String(m.userId),
    title: m.title || '',
    isPrimary: m.isPrimary,
  };
  dialogRef.value?.open();
};

const saveMember = async () => {
  try {
    if (editingId.value) {
      await memberStore.update({
        id: editingId.value,
        title: memberForm.value.title.trim() || null,
        isPrimary: memberForm.value.isPrimary,
      });
    } else {
      if (!memberForm.value.userId) return;
      await memberStore.create({
        departmentId: selectedDeptId.value,
        userId: Number(memberForm.value.userId),
        title: memberForm.value.title.trim() || null,
        isPrimary: memberForm.value.isPrimary,
      });
    }
    dialogRef.value?.close();
    fetchMembers();
    fetchDepartments();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeMember = async m => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.removeMemberConfirm)) return;
  await memberStore.delete(m.id);
  fetchDepartments();
  useAlert(L.saved);
};

const initial = name => (name || '?').trim().charAt(0).toUpperCase();

onMounted(async () => {
  fetchDepartments();
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between gap-3 flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        v-if="canManage"
        :label="L.addRoot"
        icon="i-lucide-plus"
        color="iris"
        @click="addRoot"
      />
    </div>

    <div
      v-if="!canManage"
      class="px-4 sm:px-6 py-2 text-xs bg-n-iris-3 text-n-iris-11"
    >
      {{ L.readonly }}
    </div>

    <div class="flex flex-col md:flex-row flex-1 min-h-0">
      <!-- 左：部门树 -->
      <aside
        class="flex flex-col flex-shrink-0 w-full max-h-64 border-b md:max-h-none md:w-80 md:border-b-0 md:border-r border-n-weak bg-n-solid-1"
      >
        <div class="flex-1 p-3 overflow-y-auto">
          <div
            v-if="isFetching"
            class="p-6 text-sm text-center text-n-slate-11"
          >
            {{ '…' }}
          </div>
          <div
            v-else-if="!tree.length"
            class="p-6 text-sm text-center text-n-slate-10"
          >
            {{ L.emptyTree }}
          </div>
          <template v-else>
            <div
              v-for="node in tree"
              :key="node.id"
              class="flex items-center pl-2 pr-1.5 rounded-lg cursor-pointer group transition-colors"
              :class="[
                selectedDeptId === node.id
                  ? 'bg-n-iris-3'
                  : 'hover:bg-n-alpha-1',
                node.depth === 0 ? 'py-1.5 mt-3 first:mt-0' : 'py-1.5',
              ]"
              @click="selectDept(node)"
            >
              <span
                v-for="level in node.depth"
                :key="level"
                aria-hidden="true"
                class="self-stretch flex-shrink-0 w-4 ml-2 -my-1.5 border-l border-n-slate-4"
              />
              <button
                v-if="node.hasChildren"
                class="flex items-center justify-center flex-shrink-0 size-5 mr-1 rounded-md text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                @click.stop="toggleCollapse(node)"
              >
                <Icon
                  :icon="
                    collapsedIds.has(node.id)
                      ? 'i-lucide-chevron-right'
                      : 'i-lucide-chevron-down'
                  "
                  class="size-3.5"
                />
              </button>
              <span
                v-else
                aria-hidden="true"
                class="flex-shrink-0 size-5 mr-1"
              />
              <span
                v-if="node.depth === 0"
                class="flex items-center justify-center flex-shrink-0 size-6 mr-2 rounded-md transition-colors"
                :class="
                  selectedDeptId === node.id
                    ? 'bg-n-iris-9 text-white'
                    : 'bg-n-iris-3 text-n-iris-11'
                "
              >
                <Icon
                  :icon="
                    isPersonNode(node)
                      ? 'i-lucide-user-round'
                      : 'i-lucide-building-2'
                  "
                  class="size-3.5"
                />
              </span>
              <Icon
                v-else-if="isPersonNode(node)"
                icon="i-lucide-user-round"
                class="size-4 flex-shrink-0 mr-2"
                :class="
                  selectedDeptId === node.id
                    ? 'text-n-iris-11'
                    : 'text-n-slate-10'
                "
              />
              <Icon
                v-else
                :icon="
                  node.hasChildren && !collapsedIds.has(node.id)
                    ? 'i-lucide-folder-open'
                    : 'i-lucide-folder'
                "
                class="size-4 flex-shrink-0 mr-2"
                :class="
                  selectedDeptId === node.id
                    ? 'text-n-iris-11'
                    : 'text-n-slate-10'
                "
              />
              <span
                class="flex-1 truncate"
                :class="[
                  node.depth === 0
                    ? 'text-sm font-semibold text-n-slate-12'
                    : 'text-sm text-n-slate-12',
                ]"
              >
                {{ node.name }}
              </span>
              <span
                v-if="node.memberCount"
                class="flex-shrink-0 px-1.5 py-0.5 mr-0.5 text-[10px] leading-none rounded-full bg-n-alpha-2 text-n-slate-11 tabular-nums"
              >
                {{ node.memberCount }}
              </span>
              <template v-if="canManage">
                <button
                  class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
                  :title="L.addChild"
                  @click.stop="addChild(node)"
                >
                  <Icon icon="i-lucide-plus" class="size-4" />
                </button>
                <button
                  class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
                  :title="L.rename"
                  @click.stop="renameDept(node)"
                >
                  <Icon icon="i-lucide-pencil" class="size-4" />
                </button>
                <button
                  class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
                  :title="L.move"
                  @click.stop="moveDept(node)"
                >
                  <Icon icon="i-lucide-corner-down-right" class="size-4" />
                </button>
                <button
                  class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
                  :title="L.remove"
                  @click.stop="deleteDept(node)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </template>
            </div>
          </template>
        </div>
      </aside>

      <!-- 右：成员 -->
      <section class="flex flex-col flex-1 min-w-0">
        <div
          v-if="!selectedDept"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <Icon icon="i-lucide-users" class="size-12 opacity-40" />
          <p class="text-sm">{{ L.selectHint }}</p>
        </div>

        <template v-else>
          <div
            class="flex flex-wrap items-center gap-x-4 sm:gap-x-6 gap-y-2 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak"
          >
            <h2 class="text-base font-medium text-n-slate-12">
              {{ selectedDept.name }}
            </h2>
            <div class="flex items-center flex-shrink-0 gap-2">
              <span class="text-xs whitespace-nowrap text-n-slate-10">{{
                L.leader
              }}</span>
              <SelectCard
                v-if="canManage"
                :model-value="
                  selectedDept.leaderId ? String(selectedDept.leaderId) : ''
                "
                :options="leaderOptions"
                trigger-class="w-40"
                @update:model-value="setLeader"
              />
              <span v-else class="text-xs text-n-slate-12">
                {{ selectedDept.leaderName || L.noLeader }}
              </span>
            </div>
            <span class="flex-1" />
            <Button
              v-if="canManage"
              :label="L.addChild"
              icon="i-lucide-folder-plus"
              size="sm"
              variant="faded"
              color="slate"
              @click="addChild(selectedDept)"
            />
            <Button
              v-if="canManage"
              :label="L.addMember"
              icon="i-lucide-user-plus"
              size="sm"
              color="iris"
              @click="openAddMember"
            />
          </div>

          <div class="flex-1 p-4 sm:p-6 overflow-y-auto">
            <div
              v-if="!members.length"
              class="p-8 text-sm text-center text-n-slate-10"
            >
              {{ L.emptyMembers }}
            </div>
            <div v-else class="flex flex-col gap-2">
              <div
                v-for="m in members"
                :key="m.id"
                class="flex items-center gap-3 p-3 border rounded-xl border-n-weak bg-n-solid-1"
              >
                <div
                  class="flex items-center justify-center flex-shrink-0 text-sm font-medium rounded-full size-9 bg-n-iris-4 text-n-iris-11"
                >
                  {{ initial(m.userName) }}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium truncate text-n-slate-12">
                      {{ m.userName }}
                    </span>
                    <span
                      v-if="m.isPrimary"
                      class="px-1.5 py-0.5 rounded text-[10px] bg-n-iris-3 text-n-iris-11"
                    >
                      {{ L.primary }}
                    </span>
                  </div>
                  <div class="text-xs truncate text-n-slate-10">
                    {{ m.title ? `${m.title} · ${m.userEmail}` : m.userEmail }}
                  </div>
                </div>
                <template v-if="canManage">
                  <button
                    class="text-n-slate-10 hover:text-n-iris-11"
                    :title="L.editMember"
                    @click="openEditMember(m)"
                  >
                    <Icon icon="i-lucide-pencil" class="size-4" />
                  </button>
                  <button
                    class="text-n-slate-10 hover:text-n-ruby-11"
                    :title="L.remove"
                    @click="removeMember(m)"
                  >
                    <Icon icon="i-lucide-x" class="size-4" />
                  </button>
                </template>
              </div>
            </div>
          </div>
        </template>
      </section>
    </div>

    <Dialog
      ref="dialogRef"
      :title="editingId ? L.editMember : L.addMember"
      confirm-button-color="iris"
      @confirm="saveMember"
    >
      <div class="flex flex-col gap-4">
        <div v-if="!editingId">
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.memberLabel }}
          </label>
          <Select
            v-model="memberForm.userId"
            class="w-full"
            :options="
              assignableAgents.map(a => ({
                value: String(a.id),
                label: a.name,
              }))
            "
          />
        </div>
        <div v-else class="text-sm text-n-slate-11">
          {{ members.find(x => x.id === editingId)?.userName }}
        </div>
        <Input v-model="memberForm.title" :label="L.titleLabel" />
        <label
          class="inline-flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
        >
          <input
            v-model="memberForm.isPrimary"
            type="checkbox"
            class="rounded accent-n-iris-9"
          />
          {{ L.primary }}
        </label>
      </div>
    </Dialog>

    <!-- 移动部门：选择新的上级（任意层级），后端防环校验兜底 -->
    <Dialog
      ref="moveDialogRef"
      :title="movingDept ? `${L.moveTitle}：${movingDept.name}` : L.moveTitle"
      confirm-button-color="iris"
      @confirm="confirmMove"
    >
      <div>
        <label class="block mb-0.5 text-heading-3 text-n-slate-12">
          {{ L.moveTargetLabel }}
        </label>
        <Select
          v-model="moveTargetId"
          class="w-full"
          :options="moveTargetOptions"
        />
      </div>
    </Dialog>
  </div>
</template>
