<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// 「列」显隐面板。配合 useOrderableColumns 用：那个 composable 已经把列序拖拽和显隐
// 都算好了，这里只负责那颗按钮和勾选面板。
//
// MES 的几张表各自内联了一份同样的 UI；财务这边是第 4 处，再抄一遍就该收口了。
// 已有的那几页先不动——它们在跑着，改了没收益只有风险。
defineProps({
  // useOrderableColumns 的 orderedColumns（含隐藏的，面板里要能勾回来）
  columns: { type: Array, required: true },
  isHidden: { type: Function, required: true },
  hiddenCount: { type: Number, default: 0 },
});
const emit = defineEmits(['toggle', 'showAll']);
const open = ref(false);
</script>

<template>
  <div class="relative">
    <Button
      :label="hiddenCount ? `列（收起 ${hiddenCount}）` : '列'"
      variant="outline"
      color="slate"
      size="sm"
      class="btn-ink"
      icon="i-lucide-columns-3"
      @click="open = !open"
    />
    <!-- 透明兜底层：点面板外面收起来，省掉一个全局 click 监听 -->
    <div v-if="open" class="fixed inset-0 z-10" @click="open = false" />
    <div
      v-if="open"
      class="absolute right-0 z-20 flex flex-col gap-1 p-2 mt-1 overflow-y-auto border shadow-lg top-full w-52 max-h-96 rounded-xl border-n-weak bg-n-solid-1"
    >
      <label
        v-for="col in columns"
        :key="`vis-${col.key}`"
        class="flex items-center gap-2 px-2 py-1 rounded cursor-pointer text-label-small hover:bg-n-alpha-1"
      >
        <input
          type="checkbox"
          :checked="!isHidden(col.key)"
          @change="emit('toggle', col.key)"
        />
        {{ col.label }}
      </label>
      <button
        class="px-2 py-1 mt-1 text-left border-t text-label-small text-n-slate-11 border-n-weak hover:text-n-slate-12"
        @click="emit('showAll')"
      >
        全部显示
      </button>
    </div>
  </div>
</template>
