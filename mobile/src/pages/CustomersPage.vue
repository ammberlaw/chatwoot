<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import { fetchCustomers } from '@/api/crm';
import { countryLabel, CUSTOMER_STATUS_LABELS } from '@/constants/crm';
import { money, num } from '@/utils/format';
import { avatarTint, avatarText } from '@/utils/avatar';

defineOptions({ name: 'CustomersPage' });

const PER_PAGE = 20;

// 视图 = 列表接口的 filter 参数
const VIEWS = [
  { value: 'mine', label: '我的' },
  { value: '', label: '全部' },
  { value: 'public_pool', label: '公海' },
];

// 只列后端白名单里确实支持的排序列，不放点了没反应的项
const SORTS = [
  { key: 'last_touch', label: '最近跟进' },
  { key: 'deal_amount', label: '成交金额' },
  { key: 'deal_count', label: '成交订单数' },
  { key: 'name', label: '客户名' },
  { key: '', label: '最近更新' },
];

// 成交客户＝终态正面，给最重的黑；其余中性。不让状态色喧宾夺主。
const STATUS_TONE = {
  WON: 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)]',
  LOST: 'bg-[color:var(--pb-danger)]/10 text-[color:var(--pb-danger)]',
};

const router = useRouter();
const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('mine');
const keyword = ref('');
const sort = ref('last_touch');
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);
const sortSheet = ref(false);

const hasMore = computed(() => list.value.length < total.value);
const sortLabel = computed(() => SORTS.find(s => s.key === sort.value)?.label || '排序');

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
      sort: sort.value || undefined,
      direction: sort.value ? 'desc' : undefined,
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

const switchView = key => {
  if (view.value === key) return;
  view.value = key;
  load();
};

const applySort = key => {
  sort.value = key;
  sortSheet.value = false;
  load();
};

// 未成交客户整列都是 ¥0，纯噪音；有金额才显示，没有就明说「未设置金额」
const dealAmount = micros => (num(micros) > 0 ? money(micros) : '');
const statusLabel = code => CUSTOMER_STATUS_LABELS[code] || '';
const subtitleOf = c =>
  [countryLabel(c.trade_country), c.primary_contact_name].filter(Boolean).join(' · ');

const open = id => router.push({ name: 'customer-detail', params: { id } });

onMounted(load);
onActivated(() => {
  if (!loading.value) load();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="客户">
      <template #actions>
        <button
          type="button"
          aria-label="新建客户"
          class="wt-fab-round wt-press"
          @click="router.push({ name: 'customer-new' })"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-none px-4 pb-2">
      <div class="wt-search">
        <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-search" />
        <input
          v-model="keyword"
          type="search"
          enterkeyhint="search"
          placeholder="搜索客户 / 联系人 / 邮箱"
          class="flex-1 min-w-0 text-[15px] bg-transparent outline-none text-[color:var(--pb-ink)] placeholder:text-[color:var(--pb-ink-3)]"
          @search="load()"
          @keyup.enter="load()"
        />
      </div>

      <!-- 视图分段：凹槽 + 深色药丸 -->
      <div class="flex gap-1 p-1 mt-2.5 rounded-full pb-well">
        <button
          v-for="v in VIEWS"
          :key="v.value"
          type="button"
          class="flex-1 rounded-full h-9 text-[13px] transition-colors"
          :class="
            view === v.value
              ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)] font-semibold'
              : 'text-[color:var(--pb-ink-2)] font-medium'
          "
          @click="switchView(v.value)"
        >
          {{ v.label }}
        </button>
      </div>

      <div class="flex items-center justify-between mt-2.5">
        <span class="text-[13px] text-[color:var(--pb-ink-3)]">共 {{ total }} 家</span>
        <button
          type="button"
          class="flex items-center gap-1 text-[13px] text-[color:var(--pb-ink-2)] wt-link"
          @click="sortSheet = true"
        >
          {{ sortLabel }}
          <span class="size-3.5 i-lucide-arrow-up-down" />
        </button>
      </div>
    </div>

    <div class="flex-1 min-h-0 px-4 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="没有符合条件的客户"
        @retry="load()"
      >
        <!-- 每家一张独立白卡（不是连续列表）：客户之间是并列关系，
             分成卡片比一条条挤在一起更好扫，也留得下金额和状态两个右侧信息。 -->
        <ul class="flex flex-col gap-2.5">
          <li v-for="c in list" :key="c.id">
            <button
              type="button"
              class="flex items-center w-full gap-3 px-3.5 py-3 text-left wt-glass wt-press"
              @click="open(c.id)"
            >
              <span
                class="grid flex-none rounded-full size-10 place-items-center text-[15px] font-semibold"
                :class="[avatarTint(c.name).bg, avatarTint(c.name).fg]"
              >
                {{ avatarText(c.name) }}
              </span>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span
                    class="flex-1 min-w-0 truncate text-[15px] font-semibold leading-5 text-[color:var(--pb-ink)]"
                  >
                    {{ c.name }}
                  </span>
                  <span
                    class="flex-none text-[15px] font-semibold leading-5 tabular-nums"
                    :class="
                      dealAmount(c.deal_total_amount_micros)
                        ? 'text-[color:var(--pb-ink)]'
                        : 'text-[color:var(--pb-ink-3)] font-normal text-[12px]'
                    "
                  >
                    {{ dealAmount(c.deal_total_amount_micros) || '未设置金额' }}
                  </span>
                </div>

                <div class="flex items-center gap-2 mt-1">
                  <span class="flex-1 min-w-0 truncate text-[13px] text-[color:var(--pb-ink-3)]">
                    {{ subtitleOf(c) || '—' }}
                  </span>
                  <span
                    v-if="statusLabel(c.customer_status)"
                    class="flex-none px-2 rounded-full text-[12px] leading-5"
                    :class="
                      STATUS_TONE[c.customer_status] ||
                      'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'
                    "
                  >
                    {{ statusLabel(c.customer_status) }}
                  </span>
                </div>
              </div>

              <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
            </button>
          </li>
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="w-full py-3 text-[15px] text-[color:var(--pb-ink-2)] active:opacity-50"
          :disabled="loadingMore"
          @click="page += 1; load({ append: true })"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-36" />
      </DataState>
    </div>

    <AppSheet :open="sortSheet" title="排序" @close="sortSheet = false">
      <ul class="overflow-hidden wt-card">
        <li v-for="(s, i) in SORTS" :key="s.key">
          <button
            type="button"
            class="flex items-center w-full gap-3 px-4 py-3 text-left active:bg-[color:var(--pb-fill)]"
            :class="i ? 'border-t-[0.5px] border-[color:var(--pb-sep)]' : ''"
            @click="applySort(s.key)"
          >
            <span class="flex-1 text-[17px] tracking-[-0.43px] text-[color:var(--pb-ink)]">
              {{ s.label }}
            </span>
            <span
              v-if="sort === s.key"
              class="flex-none size-5 text-[color:var(--pb-ink)] i-lucide-check"
            />
          </button>
        </li>
      </ul>
    </AppSheet>
  </div>
</template>
