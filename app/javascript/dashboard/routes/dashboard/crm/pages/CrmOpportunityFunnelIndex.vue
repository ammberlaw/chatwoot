<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';

const { t } = useI18n();
const { accountId } = useAccount();
const store = useCrmOpportunitiesStore();

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
    team_id: selectedTeamId.value || undefined,
    owner_id: selectedOwnerId.value || undefined,
  });

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
const openEditDialog = record => createDialogRef.value?.open(record);

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
  { key: 'SAMPLING', label: '样品中', color: 'bg-n-amber-9' },
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
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
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
        <Select
          :model-value="selectedTeamId"
          :options="teamOptions"
          @update:model-value="setTeam"
        />
        <Select
          v-if="selectedTeamId"
          :model-value="selectedOwnerId"
          :options="ownerOptions"
          @update:model-value="setOwner"
        />
        <Button
          :label="t('CRM.OPPORTUNITIES.NEW')"
          icon="i-lucide-plus"
          color="amber"
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
            class="p-4 transition-all border shadow-sm cursor-pointer bg-n-solid-1 rounded-xl border-n-weak hover:border-n-amber-8 hover:shadow-md"
            draggable="true"
            @dragstart="dragId = item.id"
            @click="openEditDialog(item)"
          >
            <!-- 阶段颜色小圈 + 标题 -->
            <div class="flex items-start gap-2">
              <span
                class="mt-1 rounded-full shrink-0 size-2.5"
                :class="col.color"
              />
              <div
                class="text-sm font-semibold leading-snug text-n-slate-12 line-clamp-2"
              >
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
