<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchRecords } from '@/api/crm';
import { RECORDS } from '@/constants/records';

defineOptions({ name: 'RecordListPage' });

const PER_PAGE = 20;

const route = useRoute();
const router = useRouter();

// 路由 meta.kind 决定这一页是商机/订单/报价/PI
const kind = computed(() => route.meta.kind);
const cfg = computed(() => RECORDS[kind.value]);

const list = ref([]);
const total = ref(0);
const page = ref(1);
const status = ref('');
const keyword = ref('');
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => list.value.length < total.value);
const statusOptions = computed(() => [
  { value: '', label: '全部' },
  ...Object.entries(cfg.value.statusLabels).map(([value, label]) => ({ value, label })),
]);

const load = async ({ append = false } = {}) => {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    // 商机的状态参数叫 sales_stage，其余叫 status
    const statusParam = cfg.value.statusKey === 'sales_stage' ? 'sales_stage' : 'status';
    const r = await fetchRecords(kind.value, {
      page: page.value,
      per_page: PER_PAGE,
      [statusParam]: status.value || undefined,
      q: cfg.value.searchable && keyword.value ? keyword.value : undefined,
    });
    const rows = r.data?.payload || [];
    list.value = append ? [...list.value, ...rows] : rows;
    total.value = r.data?.meta?.count ?? rows.length;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    if (!append) failed.value = true;
  } finally {
    loading.value = false;
    loadingMore.value = false;
  }
};

const loadMore = () => {
  page.value += 1;
  load({ append: true });
};

const switchStatus = v => {
  if (status.value === v) return;
  status.value = v;
  load();
};

// 同一个组件服务四个路由，切换单据类型时要整个重来
watch(kind, () => {
  list.value = [];
  status.value = '';
  keyword.value = '';
  load();
});

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="cfg.title" :subtitle="total ? `共 ${total} 单` : ''">
      <template #below>
        <div v-if="cfg.searchable" class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-n-slate-10 i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              enterkeyhint="search"
              placeholder="搜单号 / 客户"
              class="pl-9 wt-field"
              @search="load()"
              @keyup.enter="load()"
            />
          </div>
        </div>
        <div class="flex items-center gap-2 px-4 pb-3 overflow-x-auto [&::-webkit-scrollbar]:hidden">
          <button
            v-for="o in statusOptions"
            :key="o.value"
            type="button"
            class="flex-none h-8 px-3 text-sm leading-none rounded-full"
            :class="
              status === o.value
                ? 'bg-n-iris-9 text-white font-medium'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
            @click="switchStatus(o.value)"
          >
            {{ o.label }}
          </button>
        </div>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        :empty-text="`没有符合条件的${cfg.title}`"
        @retry="load()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="r in list" :key="r.id">
            <button
              type="button"
              class="w-full p-3 text-left wt-card active:bg-n-alpha-1"
              @click="router.push({ name: `${kind}-detail`, params: { id: r.id } })"
            >
              <div class="flex items-start gap-3">
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-n-slate-12">
                    {{ cfg.row(r).title }}
                  </div>
                  <div class="mt-0.5 text-xs truncate text-n-slate-11">
                    {{ cfg.row(r).subtitle }}
                  </div>
                </div>
                <div class="flex-none text-right">
                  <div class="text-sm font-semibold text-n-slate-12">
                    {{ cfg.row(r).amount }}
                  </div>
                  <span
                    v-if="cfg.statusLabels[r[cfg.statusKey]]"
                    class="inline-block mt-1 px-1.5 py-0.5 text-[11px] rounded-md"
                    :class="cfg.statusTone[r[cfg.statusKey]] || 'bg-n-alpha-1 text-n-slate-11'"
                  >
                    {{ cfg.statusLabels[r[cfg.statusKey]] }}
                  </span>
                </div>
              </div>
            </button>
          </li>
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="w-full mt-3 wt-btn-ghost"
          :disabled="loadingMore"
          @click="loadMore"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
