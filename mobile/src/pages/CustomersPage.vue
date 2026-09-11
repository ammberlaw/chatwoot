<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchCustomers } from '@/api/crm';
import { COUNTRY_LABELS, CUSTOMER_STATUS_LABELS } from '@/constants/crm';

defineOptions({ name: 'CustomersPage' });

const PER_PAGE = 20;

// 视图 = 列表接口的 filter 参数
const VIEWS = [
  { key: 'mine', label: '我的' },
  { key: '', label: '全部' },
  { key: 'public_pool', label: '公海' },
];

const router = useRouter();
const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('mine');
const keyword = ref('');
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => list.value.length < total.value);

const load = async ({ append = false } = {}) => {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchCustomers({
      per_page: PER_PAGE,
      page: page.value,
      filter: view.value || undefined,
      q: keyword.value || undefined,
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

const switchView = key => {
  if (view.value === key) return;
  view.value = key;
  load();
};

const money = micros =>
  `¥${Math.round((micros || 0) / 1e6).toLocaleString('zh-CN')}`;
const countryLabel = code => COUNTRY_LABELS[code] || code || '—';
const statusLabel = code => CUSTOMER_STATUS_LABELS[code] || '';

const open = id => router.push({ name: 'customer-detail', params: { id } });

onMounted(load);
// keep-alive 页返回时刷新，让新建/编辑的改动立刻反映在列表
onActivated(() => {
  if (!loading.value) load();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="客户" :subtitle="total ? `共 ${total} 家` : ''">
      <template #actions>
        <button
          type="button"
          aria-label="新建客户"
          class="grid rounded-full size-9 place-items-center text-n-iris-11 active:bg-n-alpha-1"
          @click="router.push({ name: 'customer-new' })"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>

      <template #below>
        <div class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-n-slate-10 i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              enterkeyhint="search"
              placeholder="搜客户名 / 联系人 / 邮箱 / 电话"
              class="pl-9 wt-field"
              @search="load()"
              @keyup.enter="load()"
            />
          </div>
        </div>
        <div class="flex items-center gap-2 px-4 pb-3">
          <button
            v-for="v in VIEWS"
            :key="v.key"
            type="button"
            class="h-8 px-3 text-sm leading-none rounded-full"
            :class="
              view === v.key
                ? 'bg-n-iris-9 text-white font-medium'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
            @click="switchView(v.key)"
          >
            {{ v.label }}
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
        empty-text="没有符合条件的客户"
        @retry="load()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="c in list" :key="c.id">
            <button
              type="button"
              class="w-full p-3 text-left wt-card active:bg-n-alpha-1"
              @click="open(c.id)"
            >
              <div class="flex items-start gap-3">
                <div class="flex-1 min-w-0">
                  <div class="font-semibold truncate text-n-slate-12">
                    {{ c.name }}
                  </div>
                  <div class="mt-0.5 text-xs truncate text-n-slate-11">
                    {{ countryLabel(c.trade_country) }}
                    <template v-if="c.primary_contact_name">
                      · {{ c.primary_contact_name }}
                    </template>
                  </div>
                </div>
                <div class="flex-none text-right">
                  <div class="text-sm font-semibold text-n-slate-12">
                    {{ money(c.deal_total_amount_micros) }}
                  </div>
                  <div
                    v-if="statusLabel(c.customer_status)"
                    class="mt-0.5 text-xs text-n-slate-10"
                  >
                    {{ statusLabel(c.customer_status) }}
                  </div>
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
