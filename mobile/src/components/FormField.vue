<script setup>
defineProps({
  label: { type: String, required: true },
  required: { type: Boolean, default: false },
  hint: { type: String, default: '' },
});
</script>

<template>
  <label class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-[color:var(--pb-ink-2)]">
      {{ label }}
      <span v-if="required" class="text-[#C4383C]">*</span>
    </span>
    <slot />
    <span v-if="hint" class="text-xs text-[color:var(--pb-ink-3)]">{{ hint }}</span>
  </label>
</template>
