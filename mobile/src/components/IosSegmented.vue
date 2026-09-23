<script setup>
// iOS 分段控件：灰色轨道 + 白色滑块，而不是一排彩色药丸。
defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, required: true }, // [{value,label,badge?}]
});
defineEmits(['update:modelValue']);
</script>

<template>
  <div class="flex p-1 rounded-full bg-black/[0.05]">
    <button
      v-for="o in options"
      :key="o.value"
      type="button"
      class="flex items-center justify-center flex-1 min-w-0 h-8 gap-1 transition-colors rounded-full"
      :class="
        modelValue === o.value
          ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-card)] font-semibold'
          : 'text-[color:var(--pb-ink-2)] active:opacity-60'
      "
      @click="$emit('update:modelValue', o.value)"
    >
      <span class="truncate text-[13px] leading-[18px]">{{ o.label }}</span>
      <span v-if="o.badge" class="text-[11px] leading-4 opacity-70">{{ o.badge }}</span>
    </button>
  </div>
</template>
