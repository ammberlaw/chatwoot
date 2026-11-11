<script setup>
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';
import { useCrmRole } from 'dashboard/composables/useCrmRole';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CrmOpportunityDetailDrawer from 'dashboard/components-next/CRM/CrmOpportunityDetailDrawer.vue';
import CrmOpportunityCreateDialog from 'dashboard/components-next/CRM/CrmOpportunityCreateDialog.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 嵌入「商机看板」作为列表视图时：隐藏自身标题头、去掉卡片外框、不受外层路由 query 影响。
const props = defineProps({
  embedded: { type: Boolean, default: false },
  sortKey: { type: String, default: '' },
  sortDirection: { type: String, default: 'desc' },
});

const { t } = useI18n();
const route = useRoute();
const store = useCrmOpportunitiesStore();

const createDialogRef = ref(null);
const detailDrawerRef = ref(null);
const openDetail = record => detailDrawerRef.value?.open(record);
const { isCrmSales } = useCrmRole();
// 普通业务只看个人商机：无「全部」视图，默认落在「我的」。
const normalizeFilter = value =>
  isCrmSales.value && (!value || value === 'all') ? 'mine' : value || 'all';
const activeFilter = ref(normalizeFilter(route.query.filter));

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);
const ITEMS_PER_PAGE = 20;
const currentPage = ref(1);
const totalCount = computed(() => Number(store.getMeta?.count || 0));

const STAGES = {
  NEEDS_CONFIRMED: {
    label: '需求确认（已报价）',
    class: 'bg-n-blue-3 text-n-blue-11',
  },
  SAMPLING: { label: '样品中', class: STATUS_TONE.flow },
  PENDING_PAYMENT: { label: '待付款', class: STATUS_TONE.busy },
  WON: { label: '已成交', class: STATUS_TONE.done },
  LOST: { label: '输单', class: STATUS_TONE.fail },
};

const LOSS_REASONS = {
  PRICE: '价格',
  DELIVERY: '交期',
  QUALITY: '质量',
  COMPETITOR: '竞品',
  CANCELLED: '客户取消',
  NEED_CHANGED: '需求变化',
};

const filterTabs = computed(() => [
  ...(isCrmSales.value
    ? []
    : [{ key: 'all', label: t('CRM.OPPORTUNITIES.FILTERS.ALL') }]),
  { key: 'mine', label: t('CRM.OPPORTUNITIES.FILTERS.MINE') },
  { key: 'open', label: t('CRM.OPPORTUNITIES.FILTERS.OPEN') },
]);

const fetchRecords = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  return store.get({
    page: currentPage.value,
    per_page: ITEMS_PER_PAGE,
    filter,
    sort: props.sortKey || undefined,
    direction: props.sortKey ? props.sortDirection : undefined,
  });
};

const setFilter = key => {
  activeFilter.value = key;
  currentPage.value = 1;
  fetchRecords();
};

const onPage = page => {
  currentPage.value = page;
  fetchRecords();
};
const refresh = () => {
  currentPage.value = 1;
  return fetchRecords();
};
defineExpose({ refresh });
watch(() => [props.sortKey, props.sortDirection], refresh);

const openEditDialog = record => createDialogRef.value?.open(record);

const removeRecord = async record => {
  if (
    !window.confirm(
      t('CRM.OPPORTUNITIES.DELETE.CONFIRM', { name: record.name })
    )
  )
    return;
  try {
    await store.delete(record.id);
    if (!records.value.length && currentPage.value > 1) currentPage.value -= 1;
    useAlert(t('CRM.OPPORTUNITIES.DELETE.SUCCESS'));
    fetchRecords();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.DELETE.ERROR'));
  }
};

const updateRecord = async payload => {
  try {
    await store.update(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.OPPORTUNITIES.EDIT.SUCCESS'));
    fetchRecords();
  } catch {
    useAlert(t('CRM.OPPORTUNITIES.EDIT.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    if (props.embedded) return;
    activeFilter.value = normalizeFilter(value);
    currentPage.value = 1;
    fetchRecords();
  }
);

// 定位不依赖当前页：抽屉按 ID 读取，后端继续执行商机可见范围鉴权。
watch(
  () => route.query.focus,
  async id => {
    if (props.embedded || !id) return;
    await nextTick();
    openDetail({ id });
  },
  { immediate: true }
);

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const fmtMoney = (micros, currency) =>
  micros == null ? '—' : `${CURRENCY_SYMBOL[currency] || ''}${fmtYuan(micros)}`;
const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full min-h-0 overflow-hidden"
    :class="
      embedded
        ? ''
        : 'bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5'
    "
  >
    <div
      v-if="!embedded"
      class="flex items-center justify-between flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-n-slate-12 text-heading-1">
        {{ t('CRM.OPPORTUNITIES.HEADER') }}
      </h1>
    </div>

    <div
      class="flex shrink-0 flex-wrap items-center gap-2 px-4 sm:px-6 py-3 border-b border-n-weak [.theme-classic_&]:sm:!px-8"
    >
      <div
        class="contents"
        :data-tabbar="embedded ? null : 'page'"
        :data-tabbar-theme="embedded ? null : 'classic'"
      >
        <Button
          v-for="tab in filterTabs"
          :key="tab.key"
          :label="tab.label"
          size="sm"
          :aria-selected="activeFilter === tab.key"
          :variant="activeFilter === tab.key ? 'solid' : 'faded'"
          :color="activeFilter === tab.key ? 'iris' : 'slate'"
          @click="setFilter(tab.key)"
        />
      </div>
    </div>

    <div
      class="flex-1 min-h-0 overflow-auto px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
    >
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.OPPORTUNITIES.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.OPPORTUNITIES.EMPTY') }}
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="record in records"
            :key="record.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openDetail(record)"
          >
            <div class="flex items-center gap-2">
              <span
                v-if="record.important"
                class="inline-block i-ri-star-fill size-3.5 text-[#ffc53d] shrink-0"
                :title="t('CRM.OPPORTUNITIES.IMPORTANT')"
              />
              <span class="font-medium text-n-slate-12 truncate">
                {{ record.name }}
              </span>
              <span
                class="px-2 py-0.5 shrink-0 text-label-small rounded-full"
                :class="STAGES[record.salesStage]?.class"
              >
                {{ STAGES[record.salesStage]?.label || record.salesStage }}
              </span>
              <span
                v-if="record.salesStage === 'LOST' && record.lossReason"
                class="px-1.5 py-0.5 bg-n-ruby-3 text-n-ruby-11 shrink-0 text-label-small rounded-full"
              >
                {{ LOSS_REASONS[record.lossReason] || record.lossReason }}
              </span>
              <span class="flex-1" />
              <button
                type="button"
                :title="t('CRM.OPPORTUNITIES.DELETE.LABEL')"
                class="inline-flex items-center justify-center transition-colors rounded-md shrink-0 size-7 text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                @click.stop="removeRecord(record)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </div>
            <div class="mt-1.5 text-xs text-n-slate-11">
              {{ t('CRM.OPPORTUNITIES.TABLE.CUSTOMER') }}：{{
                record.customerName || '—'
              }}
            </div>
            <div class="mt-1 flex flex-wrap gap-3 text-xs text-n-slate-11">
              <span
                >{{ t('CRM.OPPORTUNITIES.TABLE.AMOUNT') }}：{{
                  fmtMoney(record.amountMicros, record.currency)
                }}</span
              >
              <span
                >{{ t('CRM.OPPORTUNITIES.TABLE.PROBABILITY') }}：{{
                  record.probability != null ? `${record.probability}%` : '—'
                }}</span
              >
              <span
                >{{ t('CRM.OPPORTUNITIES.TABLE.EXPECTED_CLOSE') }}：{{
                  fmtDate(record.expectedCloseDate)
                }}</span
              >
            </div>
            <div class="mt-1 flex items-center gap-1.5 text-xs text-n-slate-11">
              <span>{{ t('CRM.OPPORTUNITIES.TABLE.OWNER') }}：</span>
              <span
                v-if="record.ownerName"
                class="inline-flex items-center gap-1.5"
              >
                <Avatar
                  :name="record.ownerName"
                  :src="record.ownerAvatarUrl || ''"
                  :size="20"
                  rounded-full
                />
                {{ record.ownerName }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </div>
          </div>
        </div>
        <table class="hidden md:table w-full text-sm text-left border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.NAME') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.CUSTOMER') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.STAGE') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.AMOUNT') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('CRM.OPPORTUNITIES.TABLE.PROBABILITY') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.EXPECTED_CLOSE') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CRM.OPPORTUNITIES.TABLE.OWNER') }}
              </th>
              <th class="px-3 py-2 font-medium text-right">
                {{ t('CRM.OPPORTUNITIES.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="record in records"
              :key="record.id"
              class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
              @click="openDetail(record)"
            >
              <td
                class="px-3 py-2 font-medium text-n-slate-12 whitespace-nowrap"
              >
                <span
                  v-if="record.important"
                  class="inline-block i-ri-star-fill size-3.5 text-[#ffc53d] me-1 align-[-2px]"
                  :title="t('CRM.OPPORTUNITIES.IMPORTANT')"
                />
                {{ record.name }}
              </td>
              <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
                {{ record.customerName || '—' }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <span
                  class="px-2 py-0.5 text-label-small rounded-full"
                  :class="STAGES[record.salesStage]?.class"
                >
                  {{ STAGES[record.salesStage]?.label || record.salesStage }}
                </span>
                <span
                  v-if="record.salesStage === 'LOST' && record.lossReason"
                  class="ml-1 px-1.5 py-0.5 bg-n-ruby-3 text-n-ruby-11 text-label-small rounded-full"
                >
                  {{ LOSS_REASONS[record.lossReason] || record.lossReason }}
                </span>
              </td>
              <td
                class="px-3 py-2 text-right text-n-slate-12 whitespace-nowrap"
              >
                {{ fmtMoney(record.amountMicros, record.currency) }}
              </td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{
                  record.probability != null ? `${record.probability}%` : '—'
                }}
              </td>
              <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
                {{ fmtDate(record.expectedCloseDate) }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                <span
                  v-if="record.ownerName"
                  class="inline-flex items-center gap-1.5 text-n-slate-11"
                >
                  <Avatar
                    :name="record.ownerName"
                    :src="record.ownerAvatarUrl || ''"
                    :size="20"
                    rounded-full
                  />
                  {{ record.ownerName }}
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="px-3 py-2 text-right whitespace-nowrap">
                <Button
                  :label="t('CRM.OPPORTUNITIES.VIEW')"
                  sm
                  variant="ghost"
                  color="slate"
                  @click.stop="openDetail(record)"
                />
                <Button
                  :label="t('CRM.OPPORTUNITIES.DETAIL.EDIT')"
                  sm
                  variant="ghost"
                  color="slate"
                  @click.stop="openEditDialog(record)"
                />
                <button
                  type="button"
                  :title="t('CRM.OPPORTUNITIES.DELETE.LABEL')"
                  class="inline-flex items-center justify-center transition-colors rounded-md size-7 text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                  @click.stop="removeRecord(record)"
                >
                  <Icon icon="i-lucide-trash-2" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <!-- 桌面两侧默认悬浮按钮宽 104px，分页文字和操作向内避让。 -->
    <PaginationFooter
      v-if="totalCount > 0"
      class="relative shrink-0 md:!pl-32 md:!pr-32"
      :current-page="currentPage"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      @update:current-page="onPage"
    />

    <CrmOpportunityDetailDrawer ref="detailDrawerRef" @edit="openEditDialog" />

    <CrmOpportunityCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @update="updateRecord"
    />
  </div>
</template>
