<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useOrgDepartmentsStore } from 'dashboard/stores/org/departments';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OrgChartNode from './OrgChartNode.vue';

const L = {
  header: '组织架构图',
  hint: '公司组织全景，与「部门与成员」的数据实时同步。',
  empty: '还没有部门，先到「部门与成员」创建',
  zoomIn: '放大',
  zoomOut: '缩小',
};

const deptStore = useOrgDepartmentsStore();
const departments = computed(() => deptStore.getRecords);
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
const scrollerRef = ref(null);
const centerScroll = async () => {
  await nextTick();
  const el = scrollerRef.value;
  if (el) el.scrollLeft = (el.scrollWidth - el.clientWidth) / 2;
};
watch(roots, value => {
  if (value.length) centerScroll();
});
watch(zoomIndex, centerScroll);

onMounted(() => deptStore.get());
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <div class="flex items-center gap-1">
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

    <div ref="scrollerRef" class="flex-1 overflow-auto">
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
      <div v-else class="min-w-max p-10">
        <div
          class="flex items-start justify-center gap-10 origin-top transition-transform"
          :class="zoom.class"
        >
          <OrgChartNode v-for="root in roots" :key="root.id" :node="root" />
        </div>
      </div>
    </div>
  </div>
</template>
