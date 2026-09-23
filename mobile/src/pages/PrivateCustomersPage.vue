<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import CustomerStats from '@/components/customers/CustomerStats.vue';
import CustomerSegment from '@/components/customers/CustomerSegment.vue';
import CustomerToolbar from '@/components/customers/CustomerToolbar.vue';
import CustomerRow from '@/components/customers/CustomerRow.vue';
import CustomerFilterSheet from '@/components/customers/CustomerFilterSheet.vue';
import DataState from '@/components/DataState.vue';
import { fetchCustomers, fetchCustomerStats, fetchCrmMembers } from '@/api/crm';
import { CUSTOMER_STATUS_LABELS, COUNTRY_LABELS } from '@/constants/crm';
import { useCrmOptions } from '@/composables/useCrmOptions';

defineOptions({ name: 'PrivateCustomersPage' });

const PER_PAGE = 20;

const VIEWS = [
  { value: 'mine', label: '我的客户' },
  { value: 'private', label: '团队客户' },
  { value: 'shared_out', label: '我共享出去的' },
];

const router = useRouter();
const { ensureLoaded, groupOptions, sourceOptions, productGroupOptions } = useCrmOptions();

const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('private');
const keyword = ref('');
const favoritedOnly = ref(false);
const filters = ref({});
const stats = ref({});
const previewCount = ref(0);
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);
const filterOpen = ref(false);
const owners = ref([]);

const hasMore = computed(() => list.value.length < total.value);
const filterCount = computed(() => Object.values(filters.value).filter(Boolean).length);

// 后端 COLUMN_FILTERS 支持的维度，逐一对应。国家那一组是这次一并加上去的白名单项。
const query = (f = filters.value) => ({
  filter: view.value || undefined,
  q: keyword.value.trim() || undefined,
  favorited_only: favoritedOnly.value ? '1' : undefined,
  account_owner_id: f.account_owner_id || undefined,
  status: f.status || undefined,
  source_channel: f.source_channel || undefined,
  customer_group: f.customer_group || undefined,
  product_group: f.product_group || undefined,
  trade_country: f.trade_country || undefined,
});

const filterGroups = computed(() => [
  {
    key: 'account_owner_id',
    label: '业务员',
    options: owners.value,
    empty: '你的数据范围内只有自己的客户，不需要按人筛选',
  },
  {
    key: 'status',
    label: '客户状态',
    options: Object.entries(CUSTOMER_STATUS_LABELS).map(([value, label]) => ({ value, label })),
  },
  { key: 'source_channel', label: '客户来源', options: sourceOptions.value },
  { key: 'customer_group', label: '客户分组', options: groupOptions.value },
  { key: 'product_group', label: '产品分组', options: productGroupOptions.value },
  {
    key: 'trade_country',
    label: '国家/地区',
    // 国家表很长，弹层里只给常用的一批，其余靠搜索
    options: ['CHINA', 'USA', 'UK', 'GERMANY', 'FRANCE', 'ITALY', 'SPAIN', 'UAE', 'RUSSIA', 'BRAZIL', 'MEXICO', 'INDIA', 'JAPAN', 'AUSTRALIA']
      .filter(c => COUNTRY_LABELS[c])
      .map(c => ({ value: c, label: COUNTRY_LABELS[c] })),
  },
]);

const loadStats = async (f = filters.value) => {
  try {
    const r = await fetchCustomerStats(query(f));
    stats.value = r.data || {};
    previewCount.value = r.data?.customers ?? 0;
  } catch {
    /* 概览拉不到不影响列表 */
  }
};

const load = async ({ append = false } = {}) => {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchCustomers({ ...query(), per_page: PER_PAGE, page: page.value });
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

const reload = () => {
  load();
  loadStats();
};

const switchView = v => {
  if (view.value === v) return;
  view.value = v;
  reload();
};

const toggleFavorite = () => {
  favoritedOnly.value = !favoritedOnly.value;
  reload();
};

let timer = null;
const onSearch = () => {
  clearTimeout(timer);
  timer = setTimeout(reload, 350);
};

const openFilter = async () => {
  filterOpen.value = true;
  previewCount.value = total.value;
  ensureLoaded();
  if (owners.value.length) return;
  try {
    const r = await fetchCrmMembers();
    owners.value = (r.data?.payload || r.data || [])
      .filter(m => m.name || m.crm_name)
      .map(m => ({ value: String(m.user_id || m.id), label: m.crm_name || m.name }));
  } catch {
    owners.value = [];
  }
};

const applyFilter = f => {
  filters.value = f;
  filterOpen.value = false;
  reload();
};

onMounted(reload);
onActivated(() => {
  if (!loading.value) reload();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <header class="flex-none px-4 pt-3 pb-3 pt-safeTop">
      <div class="flex items-center gap-2">
        <h1 class="flex-1 text-[32px] font-bold leading-[38px] tracking-[-0.8px] text-[color:var(--text)]">
          私海客户
        </h1>
        <button
          type="button"
          aria-label="搜索"
          class="grid flex-none rounded-full size-11 place-items-center bg-[color:var(--surface)] text-[color:var(--text)] active:opacity-60"
          @click="$refs.search?.focus()"
        >
          <span class="size-5 i-lucide-search" />
        </button>
        <button
          type="button"
          aria-label="新建客户"
          class="grid flex-none rounded-full size-11 place-items-center bg-[color:var(--black)] text-white active:opacity-80"
          @click="router.push({ name: 'customer-new' })"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </div>
    </header>

    <div class="flex-none px-4">
      <CustomerStats :stats="stats" />

      <div class="mt-[18px]">
        <CustomerSegment :model-value="view" :options="VIEWS" @update:model-value="switchView" />
      </div>

      <div class="flex items-center gap-2.5 px-4 mt-3 rounded-2xl h-12 bg-[color:var(--surface-soft)]">
        <span class="flex-none size-[18px] text-[color:var(--text-tertiary)] i-lucide-search" />
        <input
          ref="search"
          v-model="keyword"
          type="search"
          enterkeyhint="search"
          placeholder="搜索客户名称、邮箱或联系人..."
          class="flex-1 min-w-0 text-[15px] bg-transparent outline-none text-[color:var(--text)] placeholder:text-[color:var(--text-tertiary)]"
          @input="onSearch"
        />
      </div>

      <div class="mt-3.5">
        <CustomerToolbar
          :favorited-only="favoritedOnly"
          :filter-count="filterCount"
          @toggle-favorite="toggleFavorite"
          @open-filter="openFilter"
        />
      </div>
    </div>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="没有符合条件的客户"
        @retry="reload"
      >
        <ul class="flex flex-col gap-[7px]">
          <li v-for="c in list" :key="c.id">
            <CustomerRow :customer="c" @open="id => router.push({ name: 'customer-detail', params: { id } })" />
          </li>
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="w-full py-3 text-[15px] text-[color:var(--text-secondary)] active:opacity-50"
          :disabled="loadingMore"
          @click="page += 1; load({ append: true })"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-28" />
      </DataState>
    </div>

    <CustomerFilterSheet
      :open="filterOpen"
      :groups="filterGroups"
      :model-value="filters"
      :count="previewCount"
      @close="filterOpen = false"
      @preview="loadStats"
      @apply="applyFilter"
    />
  </div>
</template>
