<script setup>
defineProps({
  label: { type: String, required: true },
  required: { type: Boolean, default: false },
  hint: { type: String, default: '' },
});
</script>

<template>
  <label class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-n-slate-11">
      {{ label }}
      <span v-if="required" class="text-n-ruby-11">*</span>
    </span>
    <slot />
    <span v-if="hint" class="text-xs text-n-slate-10">{{ hint }}</span>
  </label>
</template>
