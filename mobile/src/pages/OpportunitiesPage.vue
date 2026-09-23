<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import { fetchRecords, fetchCrmMembers } from '@/api/crm';
import { OPPORTUNITY_STAGE_LABELS } from '@/constants/crm';
import { money, num, shortDate } from '@/utils/format';

defineOptions({ name: 'OpportunitiesPage' });

const PER_PAGE = 20;
const STAGES = Object.keys(OPPORTUNITY_STAGE_LABELS);

// 阶段圆点：终态用实色（赢＝深、输＝红），进行中按深浅区分推进程度。
// 只有五个阶段，颜色承载的是「走到哪一步」，不是装饰。
const STAGE_DOT = {
  NEEDS_CONFIRMED: 'bg-[color:var(--pb-ink-3)]',
  SAMPLING: 'bg-[color:var(--pb-ink-2)]',
  PENDING_PAYMENT: 'bg-[color:var(--pb-brand)]',
  WON: 'bg-[color:var(--pb-ink)]',
  LOST: 'bg-[color:var(--pb-danger)]',
};

// 状态药丸：待付款＝淡黄（要动钱了，需要盯）、赢单＝黑（终态正面）、
// 输单＝红（终态负面）、其余中性。和商机列表的圆点是同一套语义。
const STAGE_TONE = {
  NEEDS_CONFIRMED: 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]',
  SAMPLING: 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]',
  PENDING_PAYMENT: 'bg-[color:var(--pb-brand-soft)] text-[color:var(--pb-ink)]',
  WON: 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)]',
  LOST: 'bg-[color:var(--pb-danger)]/10 text-[color:var(--pb-danger)]',
};

const SORTS = [
  { key: '', label: '最近更新' },
  { key: 'amount', label: '金额从高到低' },
  { key: 'probability', label: '赢单概率从高到低' },
  { key: 'created_at', label: '最新创建' },
];

const VIEWS = [
  { key: '', label: '商机看板' },
  { key: 'mine', label: '我的商机' },
  { key: 'open', label: '商机列表' },
  { key: 'public_pool', label: '商机公海' },
];

const router = useRouter();

const view = ref('');
const keyword = ref('');
const ownerId = ref('');
const members = ref([]);
const membersError = ref('');
const filterSheet = ref(false);
const newSheet = ref(false);
const stage = ref('');
const sort = ref('');
const list = ref([]);
const total = ref(0);
const counts = ref({});
const page = ref(1);
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);
const sortSheet = ref(false);

const hasMore = computed(() => list.value.length < total.value);

const query = (extra = {}) => ({
  filter: view.value || undefined,
  q: keyword.value.trim() || undefined,
  owner_id: ownerId.value || undefined,
  sales_stage: stage.value || undefined,
  sort: sort.value || undefined,
  direction: sort.value ? 'desc' : undefined,
  ...extra,
});

const load = async ({ append = false } = {}) => {
  if (append) loadingMore.value = true;
  else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchRecords('opportunity', {
      ...query(),
      page: page.value,
      per_page: PER_PAGE,
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

// 阶段筛选条上的数字。后端没有专门的计数接口，就按阶段各要一页（per_page=1），
// 只取 meta.count，五个请求都是走索引的 count，很轻。
const loadCounts = async () => {
  const rs = await Promise.allSettled(
    STAGES.map(s =>
      fetchRecords('opportunity', { ...query(), sales_stage: s, page: 1, per_page: 1 })
    )
  );
  counts.value = Object.fromEntries(
    STAGES.map((s, i) => [s, rs[i].status === 'fulfilled' ? rs[i].value.data?.meta?.count || 0 : 0])
  );
};

const reload = () => {
  load();
  loadCounts();
};

const switchView = v => {
  if (view.value === v) return;
  view.value = v;
  stage.value = '';
  reload();
};

let timer = null;
const onSearch = () => {
  clearTimeout(timer);
  timer = setTimeout(reload, 350);
};

// 「筛选」＝按负责人。成员接口要管理员权限，业务员会 403 ——
// 那种情况下弹层直接说明原因，不给一个点开是空的按钮。
const openFilter = async () => {
  filterSheet.value = true;
  if (members.value.length || membersError.value) return;
  try {
    const r = await fetchCrmMembers();
    members.value = (r.data?.payload || r.data || []).filter(m => m.name || m.crm_name);
    if (!members.value.length) membersError.value = '没有可筛选的成员';
  } catch {
    membersError.value = '你的数据范围内只有自己的商机，不需要按人筛选';
  }
};

const applyOwner = id => {
  ownerId.value = id;
  filterSheet.value = false;
  reload();
};

const switchStage = s => {
  if (stage.value === s) return;
  stage.value = s;
  load();
};

const applySort = s => {
  sort.value = s;
  sortSheet.value = false;
  load();
};

const loadMore = () => {
  page.value += 1;
  load({ append: true });
};

const open = o => router.push({ name: 'opportunity-detail', params: { id: o.id } });

onMounted(reload);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="商机看板" subtitle="拖动卡片即可切换销售阶段">
      <template #actions>
        <button
          type="button"
          aria-label="新建商机"
          class="wt-fab-round wt-press"
          @click="newSheet = true"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-none px-4 pb-2">
      <!-- 视图分段：凹槽 + 深色药丸 -->
      <div class="flex gap-1 p-1 rounded-full pb-well">
        <button
          v-for="v in VIEWS"
          :key="v.key"
          type="button"
          class="flex-1 rounded-full h-9 text-[13px] transition-colors"
          :class="
            view === v.key
              ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)] font-semibold'
              : 'text-[color:var(--pb-ink-2)] font-medium'
          "
          @click="switchView(v.key)"
        >
          {{ v.label }}
        </button>
      </div>

      <!-- 搜索 + 筛选 + 排序 -->
      <div class="flex items-center gap-2 mt-2.5">
        <div class="wt-search">
          <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-search" />
          <input
            v-model="keyword"
            type="search"
            placeholder="搜索商机名 / 客户名…"
            class="flex-1 min-w-0 text-[15px] bg-transparent outline-none text-[color:var(--pb-ink)] placeholder:text-[color:var(--pb-ink-3)]"
            @input="onSearch"
          />
        </div>
        <button
          type="button"
          class="flex items-center gap-1.5 px-3 rounded-xl h-10 text-[13px] wt-press"
          :class="
            ownerId
              ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)]'
              : 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'
          "
          @click="openFilter"
        >
          <span class="size-4 i-lucide-filter" />
          筛选
        </button>
        <button
          type="button"
          aria-label="排序"
          class="grid rounded-xl size-10 place-items-center bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)] wt-press"
          @click="sortSheet = true"
        >
          <span class="size-4 i-lucide-arrow-up-down" />
        </button>
      </div>

      <!-- 阶段筛选：横滑药丸 + 条数 -->
      <div class="flex gap-2 px-4 py-2 -mx-4 -my-1 mt-1.5 overflow-x-auto [&::-webkit-scrollbar]:hidden">
        <button
          v-for="s in [''].concat(STAGES)"
          :key="s || 'all'"
          type="button"
          class="flex items-center flex-none gap-1.5 px-3.5 rounded-full h-8 text-[13px] transition-colors"
          :class="
            stage === s
              ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)] font-semibold'
              : 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'
          "
          @click="switchStage(s)"
        >
          {{ s ? OPPORTUNITY_STAGE_LABELS[s] : '全部' }}
          <span
            v-if="s && counts[s]"
            class="text-[11px] tabular-nums"
            :class="stage === s ? 'opacity-70' : 'text-[color:var(--pb-ink-3)]'"
          >
            {{ counts[s] }}
          </span>
        </button>
      </div>
    </div>

    <div class="flex-1 min-h-0 px-4 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="没有符合条件的商机"
        @retry="reload"
      >
        <ul class="flex flex-col gap-2.5">
          <li v-for="o in list" :key="o.id">
            <button
              type="button"
              class="w-full px-4 py-3 text-left wt-press"
              :class="
                o.important
                  ? 'rounded-2xl bg-[color:var(--pb-brand-soft)]'
                  : 'wt-glass'
              "
              @click="open(o)"
            >
              <div class="flex items-center gap-2">
                <span class="flex-none rounded-full size-2" :class="STAGE_DOT[o.sales_stage]" />
                <span
                  v-if="o.important"
                  class="flex-none size-4 text-[color:var(--pb-brand-ink)] i-ri-star-fill"
                />
                <span
                  class="flex-1 min-w-0 truncate text-[16px] font-semibold leading-[21px] tracking-[-0.3px] text-[color:var(--pb-ink)]"
                >
                  {{ o.name }}
                </span>
                <span
                  class="flex-none text-[16px] font-semibold tabular-nums text-[color:var(--pb-ink)]"
                >
                  {{ money(o.amount_micros, o.currency) }}
                </span>
                <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
              </div>

              <div class="flex items-center gap-1.5 mt-1.5 text-[13px] text-[color:var(--pb-ink-2)]">
                <span class="flex-none size-[14px] text-[color:var(--pb-ink-3)] i-lucide-building-2" />
                <span class="flex-1 min-w-0 truncate">{{ o.customer_name || '未关联客户' }}</span>
              </div>

              <div class="flex items-center gap-1.5 mt-1 text-[13px] text-[color:var(--pb-ink-2)]">
                <span class="flex-none size-[14px] text-[color:var(--pb-ink-3)] i-lucide-user" />
                <span class="flex-1 min-w-0 truncate">{{ o.owner_name || '未分配' }}</span>
                <span
                  v-if="num(o.probability)"
                  class="flex-none px-2 rounded-full text-[12px] font-semibold leading-5 tabular-nums"
                  :class="
                    o.important
                      ? 'bg-[color:var(--pb-brand)] text-black'
                      : 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink)]'
                  "
                >
                  {{ num(o.probability) }}%
                </span>
              </div>

              <div class="flex items-end gap-3 mt-1.5">
                <p class="flex-1 min-w-0 text-[13px] leading-[18px] truncate text-[color:var(--pb-ink-3)]">
                  {{
                    o.current_need ||
                    o.opportunity_remark ||
                    (o.expected_close_date ? `预计成交 ${shortDate(o.expected_close_date)}` : '—')
                  }}
                </p>
                <span class="flex-none text-[12px] leading-[18px] text-[color:var(--pb-ink-3)]">
                  {{ OPPORTUNITY_STAGE_LABELS[o.sales_stage] }}
                </span>
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
        <div class="h-36" />
      </DataState>
    </div>

    <AppSheet :open="filterSheet" title="筛选" @close="filterSheet = false">
      <p v-if="membersError" class="px-1 text-[15px] leading-6 text-[color:var(--pb-ink-3)]">
        {{ membersError }}
      </p>
      <ul v-else class="overflow-hidden wt-card">
        <li>
          <button
            type="button"
            class="flex items-center w-full gap-3 px-4 py-3 text-left active:bg-[color:var(--pb-fill)]"
            @click="applyOwner('')"
          >
            <span class="flex-1 text-[17px] tracking-[-0.43px] text-[color:var(--pb-ink)]">
              全部负责人
            </span>
            <span
              v-if="!ownerId"
              class="flex-none size-5 text-[color:var(--pb-ink)] i-lucide-check"
            />
          </button>
        </li>
        <li v-for="m in members" :key="m.id">
          <button
            type="button"
            class="flex items-center w-full gap-3 px-4 py-3 text-left border-t-[0.5px] border-[color:var(--pb-sep)] active:bg-[color:var(--pb-fill)]"
            @click="applyOwner(String(m.user_id || m.id))"
          >
            <span class="flex-1 text-[17px] tracking-[-0.43px] truncate text-[color:var(--pb-ink)]">
              {{ m.crm_name || m.name }}
            </span>
            <span
              v-if="ownerId === String(m.user_id || m.id)"
              class="flex-none size-5 text-[color:var(--pb-ink)] i-lucide-check"
            />
          </button>
        </li>
      </ul>
    </AppSheet>

    <AppSheet :open="newSheet" title="新建商机" @close="newSheet = false">
      <p class="px-1 text-[15px] leading-6 text-[color:var(--pb-ink-3)]">
        手机端的商机新建表单还没做，请先在电脑端创建。
      </p>
    </AppSheet>

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
