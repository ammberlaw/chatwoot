<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';
import CrmOpportunitiesIndex from 'dashboard/routes/dashboard/crm/pages/CrmOpportunitiesIndex.vue';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
import { fmtYuan } from 'dashboard/helper/crmMoney';

const { t } = useI18n();
const { accountId } = useAccount();
const { isCrmSales, isCrmManager } = useCrmRole();
const currentUser = useMapGetter('getCurrentUser');
const store = useCrmOpportunitiesStore();

// 视图：常规看板 / 我的商机（仅看自己名下，管理员/主管专用）/ 列表
const view = ref('board');
// 看板类视图（常规看板 + 我的商机）：都渲染 kanban、可拖拽换阶段、可点卡编辑。
const isBoardView = computed(
  () => view.value === 'board' || view.value === 'mine'
);
// 视图 → 后端 filter 参数（board/list 无 filter）。
const VIEW_FILTER = { mine: 'mine' };
// 排序：默认最近更新；可按创建时间/金额，正序倒序
const sortKey = ref('');
const sortDir = ref('desc');
// 看板快速查找：按商机名/客户名搜（后端过滤，能搜全量而非仅当前页）。
const searchQuery = ref('');

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const isCreating = computed(() => store.getUIFlags.creatingItem);

// admin 逐级筛选：团队 → 业务员
const teams = ref([]);
const selectedTeamId = ref('');
const selectedOwnerId = ref('');

const teamOptions = computed(() => [
  { value: '', label: '全部团队' },
  ...teams.value.map(tm => ({ value: String(tm.id), label: tm.name })),
]);

const ownerOptions = computed(() => {
  const team = teams.value.find(tm => String(tm.id) === selectedTeamId.value);
  return [
    { value: '', label: '全部业务员' },
    ...(team?.members || []).map(m => ({ value: String(m.id), label: m.name })),
  ];
});

// 部门主管：不筛团队，直接筛自己团队的业务员（本人 + 下属，成员接口已按辖区收口）。
const teamMembers = ref([]);
const fetchTeamMembers = async () => {
  try {
    const { data } = await CrmAgentAPI.get(accountId.value, 'team');
    teamMembers.value = data.payload || [];
  } catch {
    teamMembers.value = [];
  }
};
const managerOwnerOptions = computed(() => {
  const me = currentUser.value || {};
  const rows = teamMembers.value.filter(m => m.user_id !== me.id);
  return [
    { value: '', label: '全部业务员' },
    { value: String(me.id), label: `${me.name}（我）` },
    ...rows.map(m => ({ value: String(m.user_id), label: m.name })),
  ];
});

const createDialogRef = ref(null);
const refreshBoard = () =>
  store.get({
    page: 1,
    // 后端读 per_page（下划线）；驼峰 perPage 不生效，会回落到每页 15 条导致看板漏单。
    per_page: 100,
    filter: VIEW_FILTER[view.value] || undefined,
    // 团队/业务员筛选只在常规看板生效；「我的商机」按当前用户收口，不叠加这些。
    team_id:
      view.value === 'board' ? selectedTeamId.value || undefined : undefined,
    owner_id:
      view.value === 'board' ? selectedOwnerId.value || undefined : undefined,
    sort: sortKey.value || undefined,
    direction: sortKey.value ? sortDir.value : undefined,
    q: searchQuery.value.trim() || undefined,
  });

// 搜索防抖：输入停 300ms 再拉，避免逐字请求。
let searchTimer = null;
const onSearch = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(refreshBoard, 300);
};

const setView = value => {
  view.value = value;
  // 列表视图由嵌入的商机列表组件自行取数，无需再拉看板数据。
  if (value !== 'list') refreshBoard();
};

const sortOptions = [
  { value: '', label: t('CRM.FUNNEL.SORT_DEFAULT') },
  { value: 'created_at', label: t('CRM.FUNNEL.SORT_CREATED') },
  { value: 'amount', label: t('CRM.FUNNEL.SORT_AMOUNT') },
  { value: 'probability', label: t('CRM.FUNNEL.SORT_PROBABILITY') },
];

const setSort = value => {
  sortKey.value = value;
  refreshBoard();
};

const toggleSortDir = () => {
  sortDir.value = sortDir.value === 'desc' ? 'asc' : 'desc';
  if (sortKey.value) refreshBoard();
};

const fetchTeams = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/teams`
    );
    teams.value = data.payload || [];
  } catch {
    teams.value = [];
  }
};

const setTeam = val => {
  selectedTeamId.value = val;
  selectedOwnerId.value = '';
  refreshBoard();
};
const setOwner = val => {
  selectedOwnerId.value = val;
  refreshBoard();
};
const openCreateDialog = () => createDialogRef.value?.open();

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.OPPORTUNITIES.CREATE.SUCCESS'));
    refreshBoard();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.CREATE.ERROR'));
  }
};

// 点卡片直接编辑（与商机列表点行一致），保存后刷新看板。
const openEditDialog = record => {
  createDialogRef.value?.open(record);
};

const updateRecord = async payload => {
  try {
    await store.update(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.OPPORTUNITIES.EDIT.SUCCESS'));
    refreshBoard();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.EDIT.ERROR'));
  }
};

// 阶段点颜色：仅经典灰下 需求确认→紫、样品中→黄（blue/iris 在经典灰塌成灰）；其它主题保持原色，跟随主题实时切换。
const themeSignal = useThemeSignal();
const isClassic = computed(() => {
  void themeSignal.value;
  return isClassicTheme();
});
const STAGES = computed(() => [
  {
    key: 'NEEDS_CONFIRMED',
    label: '需求确认（已报价）',
    color: isClassic.value ? 'bg-n-violet-9' : 'bg-n-blue-9',
  },
  {
    key: 'SAMPLING',
    label: '样品中',
    color: isClassic.value ? 'bg-n-amber-9' : 'bg-n-iris-9',
  },
  { key: 'PENDING_PAYMENT', label: '待付款', color: 'bg-n-amber-9' },
  { key: 'WON', label: '已成交', color: 'bg-n-teal-9' },
  { key: 'LOST', label: '输单', color: 'bg-n-ruby-9' },
]);

// 重要商机卡：白底 + 描边 + 左侧 4px 粗条；颜色跟随主题色，
// 经典灰下 iris 会塌成灰、标不出重点，改用黄色（与图表 brand 色同口径）。
const importantCardClass = computed(() =>
  isClassic.value
    ? 'bg-n-solid-1 border-[#f0d9a0] border-l-4 border-l-[#ffc53d] hover:border-[#e8c977] hover:border-l-[#ffd161]'
    : 'bg-n-solid-1 border-n-iris-7 border-l-4 border-l-n-iris-9 hover:border-n-iris-9 hover:border-l-n-iris-10'
);

const CURRENCY_SYMBOL = { USD: '$', CNY: '¥', EUR: '€' };

const columns = computed(() =>
  STAGES.value.map(stage => {
    const items = records.value.filter(r => r.salesStage === stage.key);
    const priced = items.filter(r => r.amountMicros);
    const currencies = new Set(priced.map(r => r.currency || 'CNY'));
    // 单一币种：按原币种精确合计；多币种：按今日牌价统一折算人民币再合计（不能跨币种直加）。
    const mixed = currencies.size > 1;
    // 混币列里查不到牌价的外币商机（amountCnyMicros 为 null）不能拿原数字当人民币直加——
    // 那样合计会虚高还看不出来。一律剔除出合计，并把笔数挂到列头提示。
    const convertible = mixed
      ? priced.filter(r => r.amountCnyMicros != null)
      : priced;
    const unconverted = priced.length - convertible.length;
    const total = mixed
      ? convertible.reduce((s, r) => s + r.amountCnyMicros, 0)
      : convertible.reduce((s, r) => s + (r.amountMicros || 0), 0);
    const currency = mixed ? 'CNY' : priced[0]?.currency || 'CNY';
    return { ...stage, items, total, currency, mixed, unconverted };
  })
);

// 阶段汇总金额：完整数字（带千分位）
const totalAmount = micros => fmtYuan(micros);

// 卡片金额：货币符号 + 完整数字
const cardAmount = (micros, currency) =>
  `${CURRENCY_SYMBOL[currency] || ''}${fmtYuan(micros)}`;

// 拖拽换阶段
const dragId = ref(null);
const onDrop = async stageKey => {
  const record = records.value.find(r => r.id === dragId.value);
  dragId.value = null;
  if (!record || record.salesStage === stageKey) return;
  await store.update({ id: record.id, salesStage: stageKey });
};

onMounted(() => {
  if (isCrmManager.value) fetchTeamMembers();
  else fetchTeams();
  refreshBoard();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak"
    >
      <div class="min-w-0">
        <h1
          class="text-xl md:text-2xl font-semibold tracking-tight text-n-slate-12"
        >
          {{ t('CRM.FUNNEL.HEADER') }}
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">{{ t('CRM.FUNNEL.HINT') }}</p>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        <!-- 视图切换：看板 / 我的商机 / 列表 -->
        <div class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-2">
          <Button
            :label="t('CRM.FUNNEL.VIEW_BOARD')"
            sm
            :variant="view === 'board' ? 'solid' : 'ghost'"
            :color="view === 'board' ? 'iris' : 'slate'"
            @click="setView('board')"
          />
          <!-- 我的商机：管理员/副管/主管平时看全公司或团队，这里一键只看自己名下 -->
          <Button
            v-if="!isCrmSales"
            label="我的商机"
            sm
            :variant="view === 'mine' ? 'solid' : 'ghost'"
            :color="view === 'mine' ? 'iris' : 'slate'"
            @click="setView('mine')"
          />
          <Button
            :label="t('CRM.FUNNEL.VIEW_LIST')"
            sm
            :variant="view === 'list' ? 'solid' : 'ghost'"
            :color="view === 'list' ? 'iris' : 'slate'"
            @click="setView('list')"
          />
        </div>
        <div v-if="view !== 'list'" class="relative">
          <span
            class="absolute z-10 -translate-y-1/2 pointer-events-none i-lucide-search left-2.5 top-1/2 size-4 text-n-slate-10"
          />
          <input
            v-model="searchQuery"
            type="text"
            placeholder="搜索商机名 / 客户名…"
            class="w-48 py-0 pr-3 mb-0 text-sm rounded-lg reset-base h-9 pl-8 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
            @input="onSearch"
          />
        </div>
        <SelectCard
          :model-value="sortKey"
          :options="sortOptions"
          @update:model-value="setSort"
        />
        <Button
          v-if="sortKey"
          sm
          variant="faded"
          color="slate"
          :icon="
            sortDir === 'desc' ? 'i-lucide-arrow-down' : 'i-lucide-arrow-up'
          "
          :label="
            sortDir === 'desc'
              ? t('CRM.FUNNEL.SORT_DESC')
              : t('CRM.FUNNEL.SORT_ASC')
          "
          @click="toggleSortDir"
        />
        <SelectCard
          v-if="!isCrmSales && !isCrmManager && view === 'board'"
          :model-value="selectedTeamId"
          :options="teamOptions"
          @update:model-value="setTeam"
        />
        <SelectCard
          v-if="
            !isCrmSales && !isCrmManager && view === 'board' && selectedTeamId
          "
          :model-value="selectedOwnerId"
          :options="ownerOptions"
          @update:model-value="setOwner"
        />
        <!-- 部门主管：直接按自己团队的业务员筛选 -->
        <SelectCard
          v-if="isCrmManager && view === 'board'"
          :model-value="selectedOwnerId"
          :options="managerOwnerOptions"
          @update:model-value="setOwner"
        />
        <Button
          :label="t('CRM.OPPORTUNITIES.NEW')"
          icon="i-lucide-plus"
          color="iris"
          @click="openCreateDialog"
        />
      </div>
    </div>

    <!-- 列表视图：复用商机列表页（嵌入模式，隐藏其标题头） -->
    <CrmOpportunitiesIndex v-if="view === 'list'" embedded />

    <div v-else-if="isFetching" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.FUNNEL.LOADING') }}
    </div>

    <div
      v-else
      class="flex flex-1 gap-4 p-4 sm:p-6 overflow-x-auto md:overflow-hidden"
    >
      <div
        v-for="col in columns"
        :key="col.key"
        class="flex flex-col w-[78vw] shrink-0 md:w-auto md:flex-1 md:min-w-0 md:shrink overflow-hidden rounded-2xl bg-n-alpha-1"
        @dragover.prevent
        @drop="onDrop(col.key)"
      >
        <!-- 列头：阶段名 + 数量 + 总金额 -->
        <div class="px-4 pt-3.5 pb-3">
          <div class="flex items-center gap-2">
            <span class="rounded-full size-2" :class="col.color" />
            <span class="text-sm font-semibold text-n-slate-12">
              {{ col.label }}
            </span>
            <span
              class="px-1.5 py-0.5 ml-auto text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ col.items.length }}
            </span>
          </div>
          <div
            v-if="col.total > 0 || col.unconverted"
            class="mt-2 text-lg font-bold text-n-slate-12"
            :title="col.mixed ? '本列含多种币种，已按今日牌价折算为人民币' : ''"
          >
            <template v-if="col.total > 0">
              {{ col.mixed ? '≈' : '' }}{{ CURRENCY_SYMBOL[col.currency] || ''
              }}{{ totalAmount(col.total) }}
            </template>
            <span v-else class="text-n-slate-9">—</span>
          </div>
          <!-- 查不到牌价、没算进合计的外币商机：明着标出来，别让人以为合计是全的。
               单独占一行并 nowrap，列窄时不会折行把列头顶高、顶歪。 -->
          <div
            v-if="col.unconverted"
            class="mt-1.5 px-1.5 py-0.5 inline-flex text-xs font-medium rounded-md whitespace-nowrap bg-n-amber-3 text-n-amber-11"
            :title="`有 ${col.unconverted} 笔外币商机查不到牌价，未计入本列合计`"
          >
            {{ col.unconverted }} 笔未折算
          </div>
        </div>

        <!-- 卡片列表 -->
        <div class="flex flex-col flex-1 gap-2.5 px-2.5 pb-2.5 overflow-y-auto">
          <div
            v-for="item in col.items"
            :key="item.id"
            class="relative p-4 transition-all border shadow-sm rounded-xl group"
            :class="[
              isBoardView ? 'cursor-pointer hover:shadow-md' : 'cursor-default',
              item.important ? importantCardClass : null,
              !item.important
                ? 'bg-n-solid-1 border-n-weak hover:border-n-iris-8'
                : null,
            ]"
            :draggable="isBoardView"
            @dragstart="dragId = item.id"
            @click="openEditDialog(item)"
          >
            <!-- 阶段颜色小圈 + 标题（重要商机带星标） -->
            <div class="flex items-start gap-2">
              <span
                class="mt-1 rounded-full shrink-0 size-2.5"
                :class="col.color"
              />
              <div
                class="text-sm font-semibold leading-snug line-clamp-2 text-n-slate-12"
              >
                <span
                  v-if="item.important"
                  class="inline-block i-ri-star-fill size-3.5 text-[#ffc53d] me-1 align-[-2px]"
                  :title="t('CRM.OPPORTUNITIES.IMPORTANT')"
                />
                {{ item.name }}
              </div>
            </div>

            <!-- 客户 -->
            <div class="flex items-center gap-1.5 mt-2 text-xs text-n-slate-10">
              <span class="i-lucide-building-2 size-3.5 shrink-0" />
              <span class="truncate">
                {{ item.customerName || '未关联客户' }}
              </span>
            </div>

            <!-- 归属人（谁的商机） -->
            <div
              v-if="item.ownerName"
              class="flex items-center gap-1.5 mt-1.5 text-xs text-n-slate-10"
            >
              <span class="i-lucide-user size-3.5 shrink-0" />
              <span class="truncate">{{ item.ownerName }}</span>
            </div>

            <!-- 备注 -->
            <p
              v-if="item.opportunityRemark"
              class="mt-2 text-xs leading-relaxed text-n-slate-11 line-clamp-2"
            >
              {{ item.opportunityRemark }}
            </p>

            <div class="my-3 border-t border-n-weak" />

            <!-- 金额 + 概率 -->
            <div class="flex items-center justify-between gap-2 text-xs">
              <span
                v-if="item.amountMicros"
                class="font-semibold text-n-slate-12"
              >
                {{ cardAmount(item.amountMicros, item.currency) }}
              </span>
              <span v-else class="text-n-slate-10">未填金额</span>
              <span
                v-if="item.probability != null"
                class="flex items-center gap-1 text-n-slate-11"
              >
                <span class="i-lucide-percent size-3.5 text-n-slate-10" />
                {{ item.probability }}%
              </span>
            </div>
          </div>

          <div
            v-if="!col.items.length"
            class="px-2 py-8 text-xs text-center text-n-slate-10"
          >
            暂无商机
          </div>
        </div>
      </div>
    </div>

    <CrmOpportunityCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
      @update="updateRecord"
    />
  </div>
</template>
