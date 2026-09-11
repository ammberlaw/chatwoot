<script setup>
import { ref, watch } from 'vue';
import { fetchCustomers } from '@/api/crm';

// 关联客户的轻量选择器：输入即搜，选中后收起列表只留一行。
// 不做完整客户列表——弹层里塞不下，也没必要。
const props = defineProps({
  modelValue: { type: Object, default: null }, // { id, name }
  label: { type: String, default: '关联客户' },
});
const emit = defineEmits(['update:modelValue']);

const keyword = ref('');
const results = ref([]);
const searching = ref(false);

let timer = null;
watch(keyword, q => {
  clearTimeout(timer);
  if (!q.trim()) {
    results.value = [];
    return;
  }
  timer = setTimeout(async () => {
    searching.value = true;
    try {
      const r = await fetchCustomers({ q: q.trim(), per_page: 8 });
      results.value = r.data?.payload || [];
    } catch {
      results.value = [];
    } finally {
      searching.value = false;
    }
  }, 400);
});

const pick = c => {
  emit('update:modelValue', { id: c.id, name: c.name });
  keyword.value = '';
  results.value = [];
};
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="text-xs font-medium text-n-slate-11">{{ label }}</span>

    <div
      v-if="modelValue"
      class="flex items-center gap-2 px-3 h-11 rounded-xl bg-n-alpha-1"
    >
      <span class="flex-1 text-sm truncate text-n-slate-12">{{ modelValue.name }}</span>
      <button
        type="button"
        aria-label="取消关联"
        class="grid flex-none rounded-full size-7 place-items-center text-n-slate-10 active:bg-n-alpha-2"
        @click="emit('update:modelValue', null)"
      >
        <span class="size-4 i-lucide-x" />
      </button>
    </div>

    <template v-else>
      <input
        v-model="keyword"
        type="search"
        placeholder="输入客户名搜索"
        class="wt-field"
      />
      <p v-if="searching" class="text-xs text-n-slate-10">搜索中…</p>
      <ul v-else-if="results.length" class="overflow-hidden wt-card">
        <li v-for="c in results" :key="c.id">
          <button
            type="button"
            class="w-full px-3 py-2.5 text-sm text-left border-b last:border-b-0 border-n-weak text-n-slate-12 active:bg-n-alpha-1"
            @click="pick(c)"
          >
            {{ c.name }}
          </button>
        </li>
      </ul>
    </template>
  </div>
</template>
