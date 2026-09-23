<script setup>
// 视图分段：浅灰容器 + 当前项黑底白字，高 44。
defineProps({
  modelValue: { type: String, default: '' },
  options: { type: Array, required: true },
});
defineEmits(['update:modelValue']);
</script>

<template>
  <div class="flex gap-1 p-1 rounded-full h-11 bg-[color:var(--surface-soft)]">
    <button
      v-for="o in options"
      :key="o.value"
      type="button"
      class="flex-1 rounded-full text-[13px] transition-colors"
      :class="
        modelValue === o.value
          ? 'bg-[color:var(--black)] text-white font-semibold'
          : 'text-[color:var(--text-secondary)] font-medium'
      "
      @click="$emit('update:modelValue', o.value)"
    >
      {{ o.label }}
    </button>
  </div>
</template>
