<script setup>
import { ref, computed, onMounted } from 'vue';
import { cachedGet } from '@/api/client';
import { useAuthStore } from '@/stores/auth';

defineOptions({ name: 'CustomersPage' });

const auth = useAuthStore();
const list = ref([]);
const loading = ref(true);
const failed = ref(false);
const keyword = ref('');
const staleAt = ref(null);
const staleLabel = computed(() =>
  staleAt.value
    ? new Date(staleAt.value).toLocaleString('zh-CN', {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : ''
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await cachedGet(
      `/api/v1/accounts/${auth.accountId}/crm/customers`,
      { params: { per_page: 30, q: keyword.value || undefined } }
    );
    list.value = r.data?.payload || r.data?.data || [];
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="px-4 pt-safeTop">
    <header class="pt-3 pb-3">
      <h1 class="text-2xl font-bold text-n-slate-12">客户</h1>
    </header>

    <input
      v-model="keyword"
      type="search"
      placeholder="搜索客户名"
      class="w-full px-4 mb-3 text-base border rounded-xl h-11 border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10"
      @keyup.enter="load"
    />

    <p v-if="staleAt" class="mb-2 text-xs text-n-slate-10">
      离线，显示 {{ staleLabel }} 的数据
    </p>

    <p v-if="loading" class="py-10 text-sm text-center text-n-slate-11">
      加载中…
    </p>
    <div v-else-if="failed" class="p-5 text-center border rounded-2xl border-n-weak bg-n-solid-1">
      <p class="text-sm text-n-slate-11">加载失败</p>
      <button type="button" class="px-4 mt-3 text-sm rounded-lg h-11 text-n-iris-11 bg-n-iris-3" @click="load">
        重试
      </button>
    </div>
    <p v-else-if="!list.length" class="py-10 text-sm text-center text-n-slate-11">
      暂无客户
    </p>

    <ul v-else class="flex flex-col gap-2 pb-4">
      <li
        v-for="c in list"
        :key="c.id"
        class="p-3 border rounded-xl border-n-weak bg-n-solid-1 active:bg-n-alpha-1"
      >
        <div class="font-semibold truncate text-n-slate-12">{{ c.name }}</div>
        <div class="mt-0.5 text-xs text-n-slate-11 truncate">
          {{ c.trade_country || c.tradeCountry || '—' }}
        </div>
      </li>
    </ul>
  </div>
</template>
