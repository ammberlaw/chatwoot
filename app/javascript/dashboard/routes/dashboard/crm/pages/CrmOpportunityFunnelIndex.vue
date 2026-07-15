<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';
import { useCrmRole } from 'dashboard/composables/useCrmRole';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';

const { t } = useI18n();
const { accountId } = useAccount();
const { isCrmSales } = useCrmRole();
const store = useCrmOpportunitiesStore();

// 视图：常规看板 / 商机公海（公海全员可见全公司，认领后归入自己名下）
const view = ref('board');
// 排序：默认最近更新；可按创建时间/金额，正序倒序
const sortKey = ref('');
const sortDir = ref('desc');

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

const createDialogRef = ref(null);
const refreshBoard = () =>
  store.get({
    page: 1,
    perPage: 100,
    filter: view.value === 'pool' ? 'public_pool' : undefined,
    team_id: selectedTeamId.value || undefined,
    owner_id: selectedOwnerId.value || undefined,
    sort: sortKey.value || undefined,
    direction: sortKey.value ? sortDir.value : undefined,
  });

const setView = value => {
  view.value = value;
  refreshBoard();
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

// 点卡片直接编辑（与商机列表点行一致），保存后刷新看板。公海卡片不可编辑，走认领。
const openEditDialog = record => {
  if (view.value === 'pool') return;
  createDialogRef.value?.open(record);
};

// 公海认领 / 释放到公海
const actingId = ref(null);
const claimRecord = async record => {
  actingId.value = record.id;
  try {
    await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/opportunities/${record.id}/claim`
    );
    useAlert(t('CRM.OPPORTUNITIES.POOL.CLAIM_SUCCESS'));
    refreshBoard();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.POOL.CLAIM_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const releaseRecord = async record => {
  const ok = window.confirm(
    t('CRM.OPPORTUNITIES.POOL.RELEASE_CONFIRM', { name: record.name })
  );
  if (!ok) return;
  actingId.value = record.id;
  try {
    await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/opportunities/${record.id}/release`
    );
    useAlert(t('CRM.OPPORTUNITIES.POOL.RELEASE_SUCCESS'));
    refreshBoard();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.POOL.RELEASE_ERROR'));
  } finally {
    actingId.value = null;
  }
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

const STAGES = [
  { key: 'NEEDS_CONFIRMED', label: '需求确认（已报价）', color: 'bg-n-blue-9' },
  { key: 'SAMPLING', label: '样品中', color: 'bg-n-iris-9' },
  { key: 'WON', label: '已成交', color: 'bg-n-teal-9' },
  { key: 'LOST', label: '输单', color: 'bg-n-ruby-9' },
];

const CURRENCY_SYMBOL = { USD: '$', CNY: '¥', EUR: '€' };

const columns = computed(() =>
  STAGES.map(stage => {
    const items = records.value.filter(r => r.salesStage === stage.key);
    const total = items.reduce((s, r) => s + (r.amountMicros || 0), 0);
    const currency = items[0]?.currency || 'USD';
    return { ...stage, items, total, currency };
  })
);

// 阶段汇总金额：完整数字（带千分位）
const totalAmount = micros =>
  Math.round((micros || 0) / 1_000_000).toLocaleString();

// 卡片金额：货币符号 + 完整数字
const cardAmount = (micros, currency) =>
  `${CURRENCY_SYMBOL[currency] || ''}${Math.round((micros || 0) / 1_000_000).toLocaleString()}`;

// 拖拽换阶段
const dragId = ref(null);
const onDrop = async stageKey => {
  if (view.value === 'pool') return;
  const record = records.value.find(r => r.id === dragId.value);
  dragId.value = null;
  if (!record || record.salesStage === stageKey) return;
  await store.update({ id: record.id, salesStage: stageKey });
};

onMounted(() => {
  fetchTeams();
  refreshBoard();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12">
          {{ t('CRM.FUNNEL.HEADER') }}
        </h1>
        <p class="mt-0.5 text-sm text-n-slate-11">{{ t('CRM.FUNNEL.HINT') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <!-- 视图切换：看板 / 商机公海 -->
        <div class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-2">
          <Button
            :label="t('CRM.FUNNEL.VIEW_BOARD')"
            sm
            :variant="view === 'board' ? 'solid' : 'ghost'"
            :color="view === 'board' ? 'iris' : 'slate'"
            @click="setView('board')"
          />
          <Button
            :label="t('CRM.FUNNEL.VIEW_POOL')"
            sm
            :variant="view === 'pool' ? 'solid' : 'ghost'"
            :color="view === 'pool' ? 'iris' : 'slate'"
            @click="setView('pool')"
          />
        </div>
        <Select
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
        <Select
          v-if="!isCrmSales && view === 'board'"
          :model-value="selectedTeamId"
          :options="teamOptions"
          @update:model-value="setTeam"
        />
        <Select
          v-if="!isCrmSales && view === 'board' && selectedTeamId"
          :model-value="selectedOwnerId"
          :options="ownerOptions"
          @update:model-value="setOwner"
        />
        <Button
          v-if="view === 'board'"
          :label="t('CRM.OPPORTUNITIES.NEW')"
          icon="i-lucide-plus"
          color="iris"
          @click="openCreateDialog"
        />
      </div>
    </div>

    <div v-if="isFetching" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.FUNNEL.LOADING') }}
    </div>

    <div v-else class="flex flex-1 gap-4 p-6 overflow-x-auto">
      <div
        v-for="col in columns"
        :key="col.key"
        class="flex flex-col flex-shrink-0 overflow-hidden w-72 rounded-2xl bg-n-alpha-1"
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
            v-if="col.total > 0"
            class="mt-2 text-lg font-bold text-n-slate-12"
          >
            {{ CURRENCY_SYMBOL[col.currency] || '' }}{{ totalAmount(col.total) }}
          </div>
        </div>

        <!-- 卡片列表 -->
        <div class="flex flex-col flex-1 gap-2.5 px-2.5 pb-2.5 overflow-y-auto">
          <div
            v-for="item in col.items"
            :key="item.id"
            class="relative p-4 transition-all border shadow-sm rounded-xl group"
            :class="[
              view === 'board'
                ? 'cursor-pointer hover:shadow-md'
                : 'cursor-default',
              item.important
                ? 'bg-n-blue-4/60 backdrop-blur-xl backdrop-saturate-150 border-white/70 hover:border-n-blue-8 shadow-lg shadow-n-blue-9/15'
                : 'bg-n-solid-1 border-n-weak hover:border-n-iris-8',
            ]"
            :draggable="view === 'board'"
            @dragstart="dragId = item.id"
            @click="openEditDialog(item)"
          >
            <!-- 释放到公海（仅常规看板，悬停显示） -->
            <Button
              v-if="view === 'board'"
              sm
              ghost
              slate
              icon="i-lucide-waves"
              class="!absolute top-2 right-2 opacity-0 group-hover:opacity-100"
              :title="t('CRM.OPPORTUNITIES.POOL.RELEASE')"
              :is-disabled="actingId === item.id"
              @click.stop="releaseRecord(item)"
            />
            <!-- 阶段颜色小圈 + 标题（重要商机带星标） -->
            <div class="flex items-start gap-2">
              <span
                class="mt-1 rounded-full shrink-0 size-2.5"
                :class="col.color"
              />
              <div
                class="text-sm font-semibold leading-snug line-clamp-2"
                :class="item.important ? 'text-n-blue-12' : 'text-n-slate-12'"
              >
                <span
                  v-if="item.important"
                  class="inline-block i-lucide-star size-3.5 text-n-blue-9 me-1 align-[-2px]"
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

            <!-- 备注 -->
            <p
              v-if="item.opportunityRemark"
              class="mt-2 text-xs leading-relaxed text-n-slate-11 line-clamp-2"
            >
              {{ item.opportunityRemark }}
            </p>

            <div
              class="my-3 border-t"
              :class="item.important ? 'border-n-blue-6/60' : 'border-n-weak'"
            />

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

            <!-- 公海视图：认领 -->
            <Button
              v-if="view === 'pool'"
              :label="t('CRM.OPPORTUNITIES.POOL.CLAIM')"
              sm
              color="iris"
              class="w-full mt-3"
              :is-loading="actingId === item.id"
              @click.stop="claimRecord(item)"
            />
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
