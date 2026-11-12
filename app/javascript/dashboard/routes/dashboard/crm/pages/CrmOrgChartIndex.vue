<script setup>
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import MembershipsAPI from 'dashboard/api/org/memberships';
import OrgDepartmentPanel from 'dashboard/components-next/HR/OrgDepartmentPanel.vue';
import { useOrgDepartmentsStore } from 'dashboard/stores/org/departments';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OrgChartNode from './OrgChartNode.vue';

const { t } = useI18n();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
const { accountId } = useAccount();
const router = useRouter();
const deptStore = useOrgDepartmentsStore();
const departments = computed(() => deptStore.getRecords);
const scrollerRef = ref(null);
const query = ref('');
const allMembers = ref([]);
const membersLoading = ref(false);
const selectedId = ref(null);
const error = ref('');
let generation = 0;
const selectedDepartment = computed(() =>
  departments.value.find(department => department.id === selectedId.value)
);
const selectedMembers = computed(() =>
  allMembers.value.filter(member => member.department_id === selectedId.value)
);
const matches = computed(() => {
  const keyword = query.value.trim().toLowerCase();
  if (!keyword) return [];
  const memberDepartments = new Set(
    allMembers.value
      .filter(member =>
        `${member.user_name} ${member.title || ''}`
          .toLowerCase()
          .includes(keyword)
      )
      .map(member => member.department_id)
  );
  return departments.value.filter(
    department =>
      `${department.name} ${department.leaderName || ''}`
        .toLowerCase()
        .includes(keyword) || memberDepartments.has(department.id)
  );
});
const selectDepartment = async id => {
  selectedId.value = id;
  await nextTick();
  scrollerRef.value
    ?.querySelector(`[data-org-department-id="${Number(id)}"]`)
    ?.scrollIntoView({
      block: 'nearest',
      inline: 'center',
      behavior: 'smooth',
    });
};
const maintainDepartment = id =>
  router.push({
    name: 'crm_org_structure_index',
    params: { accountId: accountId.value },
    query: { department: id },
  });
const loadMembers = async () => {
  generation += 1;
  const request = generation;
  membersLoading.value = true;
  try {
    const { data } = await MembershipsAPI.get();
    if (request === generation) allMembers.value = data.payload || [];
  } catch {
    if (request === generation) error.value = label('FAILED');
  } finally {
    if (request === generation) membersLoading.value = false;
  }
};
const L = {
  header: '组织架构图',
  hint: '公司组织全景，与「部门与成员」的数据实时同步。',
  empty: '还没有部门，先到「部门与成员」创建',
  zoomIn: '放大',
  zoomOut: '缩小',
};

const isFetching = computed(() => deptStore.getUIFlags.fetchingList);

// 扁平部门（parentId + position）→ 嵌套树。
const roots = computed(() => {
  const byParent = {};
  departments.value.forEach(d => {
    (byParent[d.parentId || 0] ||= []).push(d);
  });
  Object.values(byParent).forEach(arr =>
    arr.sort((a, b) => a.position - b.position)
  );
  const build = d => ({ ...d, children: (byParent[d.id] || []).map(build) });
  return (byParent[0] || []).map(build);
});

// 缩放档位（transform 缩放，类名需为静态字面量供 Tailwind 收集）。
const ZOOM_LEVELS = [
  { label: '55%', class: 'scale-[0.55]' },
  { label: '70%', class: 'scale-[0.7]' },
  { label: '85%', class: 'scale-[0.85]' },
  { label: '100%', class: 'scale-100' },
];
const zoomIndex = ref(ZOOM_LEVELS.length - 1);
const zoom = computed(() => ZOOM_LEVELS[zoomIndex.value]);
const zoomIn = () => {
  if (zoomIndex.value < ZOOM_LEVELS.length - 1) zoomIndex.value += 1;
};
const zoomOut = () => {
  if (zoomIndex.value > 0) zoomIndex.value -= 1;
};

// 图比视口宽时水平居中，让根节点出现在正中；缩放后同样重新居中。
const centerScroll = async () => {
  await nextTick();
  const el = scrollerRef.value;
  if (el) el.scrollLeft = (el.scrollWidth - el.clientWidth) / 2;
};
watch(roots, value => {
  if (value.length) centerScroll();
});
watch(zoomIndex, centerScroll);

onMounted(() => {
  deptStore.get();
  loadMembers();
});
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border [.theme-classic_&]:bg-[#f7f8fa] [.theme-classic_&]:border-[#e4e7ec] [.theme-classic_&]:shadow-none bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8 [.theme-classic_&]:bg-white [.theme-classic_&]:py-5"
    >
      <div class="min-w-0">
        <h1 class="text-n-slate-12 text-heading-1">{{ L.header }}</h1>
        <p
          class="mt-0.5 text-xs text-n-slate-10 [.theme-classic_&]:text-label-small"
        >
          {{ L.hint }}
        </p>
      </div>
      <div
        class="flex items-center flex-shrink-0 gap-1 [.theme-classic_&]:rounded-xl [.theme-classic_&]:border [.theme-classic_&]:border-[#e3e6eb] [.theme-classic_&]:bg-[#f8f9fb] [.theme-classic_&]:p-1"
      >
        <button
          class="flex items-center justify-center rounded-md size-7 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:pointer-events-none"
          :title="L.zoomOut"
          :disabled="zoomIndex === 0"
          @click="zoomOut"
        >
          <Icon icon="i-lucide-zoom-out" class="size-4" />
        </button>
        <span class="w-10 text-xs text-center text-n-slate-11 tabular-nums">
          {{ zoom.label }}
        </span>
        <button
          class="flex items-center justify-center rounded-md size-7 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40 disabled:pointer-events-none"
          :title="L.zoomIn"
          :disabled="zoomIndex === ZOOM_LEVELS.length - 1"
          @click="zoomIn"
        >
          <Icon icon="i-lucide-zoom-in" class="size-4" />
        </button>
      </div>
    </div>

    <div class="border-b border-n-weak px-4 py-3 sm:px-6">
      <input
        v-model="query"
        type="search"
        :placeholder="label('DEPT_SEARCH')"
        :aria-label="label('DEPT_SEARCH')"
        class="h-10 w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 px-3 text-label"
      />
      <p v-if="error" role="alert" class="mt-2 text-label-small text-n-ruby-11">
        {{ error }}
      </p>
      <div
        v-if="query"
        class="mt-2 flex max-h-32 flex-wrap gap-2 overflow-y-auto"
      >
        <button
          v-for="department in matches"
          :key="department.id"
          class="rounded-lg bg-n-alpha-1 px-3 py-2 text-label-small"
          @click="selectDepartment(department.id)"
        >
          {{ department.name }}
        </button>
      </div>
    </div>
    <div class="flex min-h-0 flex-1 flex-col overflow-hidden md:flex-row">
      <div
        ref="scrollerRef"
        class="flex-1 overflow-auto [.theme-classic_&]:bg-[radial-gradient(#dce1e8_1px,transparent_1px)] [.theme-classic_&]:bg-[length:20px_20px]"
      >
        <div
          v-if="isFetching && !departments.length"
          class="p-10 text-sm text-center text-n-slate-11"
        >
          {{ '…' }}
        </div>
        <div
          v-else-if="!roots.length"
          class="flex flex-col items-center justify-center h-full gap-3 text-n-slate-10"
        >
          <Icon icon="i-lucide-network" class="size-12 opacity-40" />
          <p class="text-sm">{{ L.empty }}</p>
        </div>
        <div
          v-else
          class="min-w-max p-4 sm:p-10 [.theme-classic_&]:px-10 [.theme-classic_&]:py-14"
        >
          <div
            class="flex items-start justify-center gap-10 origin-top transition-transform"
            :class="zoom.class"
          >
            <OrgChartNode
              v-for="root in roots"
              :key="root.id"
              :node="root"
              @select="selectDepartment"
            />
          </div>
        </div>
      </div>
      <OrgDepartmentPanel
        v-if="selectedDepartment"
        :department="selectedDepartment"
        :members="selectedMembers"
        :loading="membersLoading"
        @close="selectedId = null"
        @maintain="maintainDepartment"
      />
    </div>
  </div>
</template>
