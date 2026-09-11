<script setup>
import FormField from '@/components/FormField.vue';

// 审批模板的动态表单字段（7 种类型）。发起与改单共用，别各写一套。
defineProps({
  fields: { type: Array, default: () => [] },
  modelValue: { type: Object, required: true },
});
</script>

<template>
  <FormField
    v-for="f in fields"
    :key="f.key"
    :label="f.label"
    :required="!!f.required"
  >
    <textarea
      v-if="f.type === 'textarea'"
      v-model="modelValue[f.key]"
      rows="4"
      class="wt-field"
    />
    <select v-else-if="f.type === 'select'" v-model="modelValue[f.key]" class="wt-field">
      <option value="">请选择</option>
      <option v-for="o in f.options || []" :key="o" :value="o">{{ o }}</option>
    </select>
    <input
      v-else-if="f.type === 'date'"
      v-model="modelValue[f.key]"
      type="date"
      class="wt-field"
    />
    <input
      v-else-if="f.type === 'datetime'"
      v-model="modelValue[f.key]"
      type="datetime-local"
      class="wt-field"
    />
    <input
      v-else-if="f.type === 'number' || f.type === 'amount'"
      v-model="modelValue[f.key]"
      type="number"
      inputmode="decimal"
      class="wt-field"
    />
    <input v-else v-model="modelValue[f.key]" type="text" class="wt-field" />
  </FormField>
</template>
