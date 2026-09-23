<script setup>
// 轻量工具条：左「只看关注」、右「筛选」。规范要求不做成两个大按钮。
defineProps({
  favoritedOnly: { type: Boolean, default: false },
  filterCount: { type: Number, default: 0 },
});
defineEmits(['toggle-favorite', 'open-filter']);
</script>

<template>
  <div class="flex items-center justify-between">
    <button
      type="button"
      class="flex items-center gap-1.5 text-[14px] transition-opacity active:opacity-50"
      :class="favoritedOnly ? 'text-[color:var(--text)] font-medium' : 'text-[color:var(--text-secondary)]'"
      @click="$emit('toggle-favorite')"
    >
      <span
        class="size-4"
        :class="favoritedOnly ? 'i-ri-heart-fill text-[color:var(--yellow-mark)]' : 'i-ri-heart-line'"
      />
      只看关注
    </button>

    <button
      type="button"
      class="flex items-center gap-0.5 text-[14px] transition-opacity active:opacity-50"
      :class="filterCount ? 'text-[color:var(--text)] font-medium' : 'text-[color:var(--text-secondary)]'"
      @click="$emit('open-filter')"
    >
      筛选<template v-if="filterCount"> {{ filterCount }}</template>
      <span class="size-4 i-lucide-chevron-right" />
    </button>
  </div>
</template>
