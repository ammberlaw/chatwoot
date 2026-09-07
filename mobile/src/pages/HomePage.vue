<script setup>
import { ref, computed, onMounted } from 'vue';
import { cachedGet } from '@/api/client';
import { useAuthStore } from '@/stores/auth';

defineOptions({ name: 'HomePage' });

const auth = useAuthStore();
const stats = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null); // 非空 = 当前展示的是缓存数据

const money = micros => `¥${Math.round((micros || 0) / 1e6).toLocaleString()}`;

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
    const r = await cachedGet(`/api/v1/accounts/${auth.accountId}/crm/stats`);
    stats.value = r.data;
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
    <header class="pt-3 pb-4">
      <h1 class="text-2xl font-bold text-n-slate-12">工作台</h1>
      <p class="mt-0.5 text-sm text-n-slate-11">
        {{ auth.user?.name || auth.user?.email || '' }}
      </p>
    </header>

    <p v-if="loading" class="py-10 text-sm text-center text-n-slate-11">
      加载中…
    </p>

    <div
      v-else-if="failed"
      class="p-5 text-center border rounded-2xl border-n-weak bg-n-solid-1"
    >
      <p class="text-sm text-n-slate-11">数据加载失败</p>
      <button
        type="button"
        class="px-4 mt-3 text-sm font-medium rounded-lg h-11 text-n-iris-11 bg-n-iris-3"
        @click="load"
      >
        重新加载
      </button>
    </div>

    <template v-else>
      <p v-if="staleAt" class="mb-2 text-xs text-n-slate-10">
        离线，显示 {{ staleLabel }} 的数据
      </p>

      <div class="grid grid-cols-2 gap-3">
      <div
        v-for="kpi in [
          { l: 'GMV', v: money(stats?.period_stats?.yearly?.amount_micros) },
          { l: '成交订单', v: stats?.period_stats?.yearly?.order_count ?? 0 },
          { l: '成交客户', v: stats?.period_stats?.yearly?.deal_customers ?? 0 },
          { l: '新客户', v: stats?.period_stats?.yearly?.new_customers ?? 0 },
        ]"
        :key="kpi.l"
        class="p-4 shadow-sm rounded-2xl bg-gradient-to-br from-n-iris-3 to-n-iris-5"
      >
        <div class="text-sm font-medium truncate text-n-slate-11">
          {{ kpi.l }}
        </div>
        <div class="mt-1 text-xl font-bold truncate text-n-slate-12">
          {{ kpi.v }}
        </div>
        </div>
      </div>
    </template>
  </div>
</template>
