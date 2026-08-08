<script setup>
import { ref, computed } from 'vue';

// Element 风格分页：共N条 ‹ 1 2 3 … N › [每页条数▾] 跳至[_]页。
// 自定义下拉（不用原生 <select>，绕开全局 select 样式规则）。
const props = defineProps({
  total: { type: Number, default: 0 },
  currentPage: { type: Number, required: true },
  pageSize: { type: Number, required: true },
  pageSizeOptions: { type: Array, default: () => [10, 15, 20, 30, 50, 100] },
});
const emit = defineEmits(['update:currentPage', 'update:pageSize']);

const totalPages = computed(() =>
  Math.max(1, Math.ceil(props.total / props.pageSize))
);

// 页码列表（超过 7 页折叠为省略号），返回数字或 'gap' 标记。
const pages = computed(() => {
  const total = totalPages.value;
  const cur = props.currentPage;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);

  let left = Math.max(2, cur - 1);
  let right = Math.min(total - 1, cur + 1);
  if (cur <= 4) {
    left = 2;
    right = 5;
  }
  if (cur >= total - 3) {
    left = total - 4;
    right = total - 1;
  }
  const list = [1];
  if (left > 2) list.push('gap-l');
  for (let i = left; i <= right; i += 1) list.push(i);
  if (right < total - 1) list.push('gap-r');
  list.push(total);
  return list;
});

const go = page => {
  const p = Number(page);
  if (p >= 1 && p <= totalPages.value && p !== props.currentPage) {
    emit('update:currentPage', p);
  }
};

// 每页条数下拉
const sizeOpen = ref(false);
const chooseSize = size => {
  sizeOpen.value = false;
  if (size !== props.pageSize) emit('update:pageSize', size);
};

// 跳至
const jumpValue = ref('');
const onJump = () => {
  const p = parseInt(jumpValue.value, 10);
  jumpValue.value = '';
  if (!Number.isNaN(p)) go(Math.min(Math.max(p, 1), totalPages.value));
};
</script>

<template>
  <div
    class="flex items-center gap-2 text-sm select-none text-n-slate-11 tabular-nums"
  >
    <span class="mr-1">共 {{ total }} 条</span>

    <!-- 上一页 -->
    <button
      type="button"
      class="flex items-center justify-center rounded-full size-8 hover:bg-n-alpha-1 disabled:opacity-40 disabled:hover:bg-transparent"
      :disabled="currentPage <= 1"
      @click="go(currentPage - 1)"
    >
      <span class="i-lucide-chevron-left size-4" />
    </button>

    <!-- 页码 -->
    <template v-for="(p, i) in pages" :key="`${p}-${i}`">
      <span
        v-if="p === 'gap-l' || p === 'gap-r'"
        class="flex items-center justify-center size-8 text-n-slate-10"
      >
        …
      </span>
      <button
        v-else
        type="button"
        class="flex items-center justify-center rounded-full min-w-[2rem] h-8 px-2"
        :class="
          p === currentPage
            ? 'bg-n-blue-3 text-n-blue-11 font-medium'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="go(p)"
      >
        {{ p }}
      </button>
    </template>

    <!-- 下一页 -->
    <button
      type="button"
      class="flex items-center justify-center rounded-full size-8 hover:bg-n-alpha-1 disabled:opacity-40 disabled:hover:bg-transparent"
      :disabled="currentPage >= totalPages"
      @click="go(currentPage + 1)"
    >
      <span class="i-lucide-chevron-right size-4" />
    </button>

    <!-- 每页条数（自定义下拉） -->
    <div class="relative ml-1">
      <button
        type="button"
        class="flex items-center gap-1 px-3 border rounded-md h-8 border-n-weak text-n-slate-12 hover:border-n-slate-6"
        @click="sizeOpen = !sizeOpen"
      >
        {{ pageSize }} 条/页
        <span
          class="size-4 text-n-slate-10 transition-transform"
          :class="sizeOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>
      <template v-if="sizeOpen">
        <div class="fixed inset-0 z-10" @click="sizeOpen = false" />
        <div
          class="absolute left-0 z-20 py-1 mb-1 overflow-hidden border rounded-lg shadow-lg bottom-full min-w-full border-n-weak bg-n-solid-1"
        >
          <button
            v-for="opt in pageSizeOptions"
            :key="opt"
            type="button"
            class="flex items-center w-full px-3 py-1.5 text-left whitespace-nowrap hover:bg-n-alpha-1"
            :class="
              opt === pageSize
                ? 'text-n-blue-11 font-medium'
                : 'text-n-slate-12'
            "
            @click="chooseSize(opt)"
          >
            {{ opt }} 条/页
          </button>
        </div>
      </template>
    </div>

    <!-- 跳至 -->
    <div class="flex items-center gap-1 ml-1">
      <span>跳至</span>
      <input
        v-model="jumpValue"
        type="number"
        min="1"
        :max="totalPages"
        class="w-12 text-center border rounded-md reset-base h-8 border-n-weak text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
        @keyup.enter="onJump"
        @blur="onJump"
      />
      <span>页</span>
    </div>
  </div>
</template>
