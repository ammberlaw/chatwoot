<script setup>
import { ref, watch } from 'vue';

// iOS 底部弹层筛选。分类用 chip，选中是黄色。底部固定「重置 / 确定（N）」。
// 只列后端 COLUMN_FILTERS 里确实支持的维度，不放点了没反应的组。
const props = defineProps({
  open: { type: Boolean, default: false },
  groups: { type: Array, default: () => [] },
  modelValue: { type: Object, default: () => ({}) },
  // 「确定」按钮上显示的条数
  count: { type: Number, default: 0 },
});
const emit = defineEmits(['close', 'apply', 'preview']);

// 弹层里先改草稿，点确定才生效——否则每点一个 chip 就重拉一次列表。
// 但「确定（N）」要显示筛完的条数，所以草稿变化时抛给父组件去试算。
const draft = ref({ ...props.modelValue });
watch(
  () => props.open,
  v => {
    if (v) draft.value = { ...props.modelValue };
  }
);
watch(draft, v => emit('preview', { ...v }), { deep: true });

const pick = (key, value) => {
  draft.value = { ...draft.value, [key]: draft.value[key] === value ? '' : value };
};
const reset = () => {
  draft.value = {};
};
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="fixed inset-0 z-50 flex flex-col justify-end">
      <div class="absolute inset-0 bg-black/35" @click="$emit('close')" />

      <div
        class="relative flex flex-col max-h-[86vh] rounded-t-[22px] bg-[color:var(--page)] pb-safeBottom"
      >
        <div class="flex justify-center pt-2.5">
          <span class="h-1 rounded-full w-9 bg-[color:var(--text-tertiary)]/45" />
        </div>

        <div class="flex items-center px-4 pt-2 pb-3">
          <span class="flex-1 text-[17px] font-semibold text-[color:var(--text)]">筛选</span>
          <button
            type="button"
            aria-label="关闭"
            class="grid rounded-full size-8 place-items-center bg-[color:var(--surface-soft)] text-[color:var(--text-secondary)] active:opacity-60"
            @click="$emit('close')"
          >
            <span class="size-4 i-lucide-x" />
          </button>
        </div>

        <div class="flex-1 min-h-0 px-4 overflow-y-auto">
          <template v-for="g in groups" :key="g.key">
            <p class="pt-4 pb-2 text-[14px] font-medium text-[color:var(--text-secondary)]">
              {{ g.label }}
            </p>
            <p v-if="!g.options.length" class="pb-1 text-[13px] text-[color:var(--text-tertiary)]">
              {{ g.empty || '暂无可选项' }}
            </p>
            <div v-else class="flex flex-wrap gap-2">
              <button
                v-for="o in g.options"
                :key="o.value"
                type="button"
                class="px-3.5 rounded-full h-9 text-[13px] transition-colors"
                :class="
                  draft[g.key] === o.value
                    ? 'bg-[color:var(--yellow)] text-black font-semibold'
                    : 'bg-[color:var(--surface)] text-[color:var(--text-secondary)]'
                "
                @click="pick(g.key, o.value)"
              >
                {{ o.label }}
              </button>
            </div>
          </template>
          <div class="h-4" />
        </div>

        <div class="flex gap-3 px-4 pt-3 pb-3 border-t-[0.5px] border-[color:var(--divider)]">
          <button
            type="button"
            class="px-6 rounded-2xl h-12 text-[15px] font-semibold bg-[color:var(--surface-soft)] text-[color:var(--text)] active:opacity-70"
            @click="reset"
          >
            重置
          </button>
          <button
            type="button"
            class="flex-1 rounded-2xl h-12 text-[15px] font-semibold bg-[color:var(--black)] text-white active:opacity-80"
            @click="$emit('apply', { ...draft })"
          >
            确定（{{ count }}）
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
