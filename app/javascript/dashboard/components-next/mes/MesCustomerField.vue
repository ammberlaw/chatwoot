<script setup>
// 客户字段：可手动输入，也可输入时从 CRM 客户里搜索选择（选中带出客户名）。
import { ref } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import CrmCustomerAPI from 'dashboard/api/crm/customers';

const model = defineModel({ type: String, default: '' });

const results = ref([]);
const open = ref(false);
let timer = null;

const runSearch = q => {
  clearTimeout(timer);
  const kw = (q || '').trim();
  if (!kw) {
    results.value = [];
    open.value = false;
    return;
  }
  timer = setTimeout(async () => {
    try {
      const { data } = await CrmCustomerAPI.get({ q: kw, page: 1 });
      results.value = (data?.payload || []).slice(0, 8);
      open.value = results.value.length > 0;
    } catch {
      results.value = [];
      open.value = false;
    }
  }, 300);
};

const onInput = v => {
  model.value = v;
  runSearch(v);
};
const pick = c => {
  model.value = c.name;
  open.value = false;
  results.value = [];
};
// 失焦稍后关闭，留出点击候选的时间。
const onBlur = () => {
  setTimeout(() => {
    open.value = false;
  }, 150);
};
</script>

<template>
  <div class="relative">
    <Input
      :model-value="model"
      placeholder="输入客户名，或从 CRM 客户中选择"
      @update:model-value="onInput"
      @focus="runSearch(model)"
      @blur="onBlur"
    />
    <ul
      v-if="open"
      class="absolute left-0 right-0 z-20 mt-1 overflow-auto border rounded-lg shadow-lg max-h-52 border-n-weak bg-n-solid-1"
    >
      <li
        v-for="c in results"
        :key="c.id"
        class="flex items-center justify-between px-3 py-2 text-sm cursor-pointer hover:bg-n-alpha-1 text-n-slate-12"
        @mousedown.prevent="pick(c)"
      >
        <span class="truncate">{{ c.name }}</span>
        <span
          v-if="c.customer_group"
          class="ml-2 text-xs shrink-0 text-n-slate-10"
        >
          {{ c.customer_group }}
        </span>
      </li>
    </ul>
  </div>
</template>
