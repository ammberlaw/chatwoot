<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';

const { t } = useI18n();
const store = useCrmOpportunitiesStore();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const STAGES = [
  { key: 'NEEDS_CONFIRMED', label: '需求确认（已报价）', color: 'bg-n-blue-9' },
  { key: 'SAMPLING', label: '样品中', color: 'bg-n-amber-9' },
  { key: 'WON', label: '已成交', color: 'bg-n-teal-9' },
  { key: 'LOST', label: '输单', color: 'bg-n-ruby-9' },
];

const columns = computed(() =>
  STAGES.map(stage => ({
    ...stage,
    items: records.value.filter(r => r.salesStage === stage.key),
  }))
);

const money = (micros, currency) =>
  micros == null ? '' : `${currency || ''} ${(micros / 1_000_000).toLocaleString()}`;

// 拖拽换阶段
const dragId = ref(null);
const onDrop = async stageKey => {
  const record = records.value.find(r => r.id === dragId.value);
  dragId.value = null;
  if (!record || record.salesStage === stageKey) return;
  await store.update({ id: record.id, salesStage: stageKey });
};

onMounted(() => store.get({ page: 1, perPage: 100 }));
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <div class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.FUNNEL.HEADER') }}
      </h1>
      <span class="text-sm text-n-slate-11">{{ t('CRM.FUNNEL.HINT') }}</span>
    </div>

    <div v-if="isFetching" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.FUNNEL.LOADING') }}
    </div>

    <div v-else class="flex flex-1 gap-3 p-4 overflow-x-auto">
      <div
        v-for="col in columns"
        :key="col.key"
        class="flex flex-col flex-shrink-0 w-56 rounded-xl bg-n-solid-2"
        @dragover.prevent
        @drop="onDrop(col.key)"
      >
        <div class="flex items-center gap-2 px-3 py-2.5">
          <span class="w-2 h-2 rounded-full" :class="col.color" />
          <span class="text-sm font-medium text-n-slate-12">{{ col.label }}</span>
          <span class="ml-auto text-xs text-n-slate-10">{{ col.items.length }}</span>
        </div>
        <div class="flex flex-col flex-1 gap-2 p-2 overflow-y-auto">
          <div
            v-for="item in col.items"
            :key="item.id"
            class="p-3 bg-white border rounded-lg shadow-sm cursor-grab border-n-weak dark:bg-n-solid-1"
            draggable="true"
            @dragstart="dragId = item.id"
          >
            <div class="text-sm font-medium text-n-slate-12">{{ item.name }}</div>
            <div v-if="item.customerName" class="mt-1 text-xs text-n-slate-11">
              {{ item.customerName }}
            </div>
            <div v-if="item.amountMicros" class="mt-1 text-xs font-medium text-n-slate-11">
              {{ money(item.amountMicros, item.currency) }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
