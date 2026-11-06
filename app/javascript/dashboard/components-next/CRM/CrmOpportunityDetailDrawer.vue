<script setup>
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import OpportunityAPI from 'dashboard/api/crm/opportunities';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';
import CrmCustomerPeekDialog from './CrmCustomerPeekDialog.vue';

const emit = defineEmits(['edit']);
const { t } = useI18n();
const dialog = ref(null);
const record = ref(null);
const loading = ref(false);
const failed = ref(false);
let requestId = 0;
const stages = {
  NEEDS_CONFIRMED: '需求确认（已报价）',
  SAMPLING: '样品中',
  PENDING_PAYMENT: '待付款',
  WON: '已成交',
  LOST: '输单',
};
const lossReasons = {
  PRICE: '价格',
  DELIVERY: '交期',
  QUALITY: '质量',
  COMPETITOR: '竞品',
  CANCELLED: '客户取消',
  NEED_CHANGED: '需求变化',
};
const formatDate = value =>
  value
    ? new Date(value).toLocaleString(undefined, {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';
const fields = computed(() => {
  const r = record.value || {};
  return [
    ['TABLE.PROBABILITY', r.probability == null ? null : `${r.probability}%`],
    [
      'TABLE.EXPECTED_CLOSE',
      r.expectedCloseDate
        ? new Date(r.expectedCloseDate).toLocaleDateString()
        : null,
    ],
    ['DETAIL.NEXT_FOLLOW_UP', formatDate(r.nextFollowUpAt)],
    ['DETAIL.CREATED', formatDate(r.createdAt)],
    ['DETAIL.UPDATED', formatDate(r.updatedAt)],
  ];
});
const notes = computed(() => {
  const r = record.value || {};
  return [
    ['FORM.REMARK', r.opportunityRemark],
    ['DETAIL.CURRENT_NEED', r.currentNeed],
    ['DETAIL.COMPETITOR', r.competitor],
    ['DETAIL.NEXT_ACTION', r.nextAction],
    ...(r.salesStage === 'LOST'
      ? [['DETAIL.LOSS_REASON', lossReasons[r.lossReason] || r.lossReason]]
      : []),
  ].filter(([, value]) => value);
});
const load = async () => {
  requestId += 1;
  const currentRequest = requestId;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await OpportunityAPI.show(record.value.id);
    if (currentRequest === requestId)
      record.value = camelcaseKeys(data, { deep: true });
  } catch {
    if (currentRequest === requestId) failed.value = true;
  } finally {
    if (currentRequest === requestId) loading.value = false;
  }
};
// 客户速览：点客户名在这张商机上面叠一层卡片，不用关掉商机跑去客户页再退回来。
const customerPeek = ref(null);
const peekCustomer = () => {
  const id = record.value?.crmCustomerId;
  if (id) customerPeek.value?.open(id);
};

const close = () => dialog.value?.close();
const open = async item => {
  record.value = item;
  await nextTick();
  if (!dialog.value.open) dialog.value.showModal();
  load();
};
const edit = () => {
  const item = record.value;
  close();
  emit('edit', item);
};
defineExpose({ open });
</script>

<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      aria-labelledby="opportunity-detail-title"
      class="fixed inset-y-2 left-auto right-2 m-0 h-[calc(100dvh-16px)] max-h-none w-[calc(100%-16px)] max-w-xl overflow-hidden rounded-3xl border border-n-weak bg-n-solid-1 p-0 text-n-slate-12 shadow-2xl backdrop:bg-black/30 sm:inset-y-4 sm:right-4 sm:h-[calc(100dvh-32px)] sm:w-[calc(100%-32px)]"
      @click="
        event => {
          if (event.target === dialog) close();
        }
      "
      @close="requestId += 1"
    >
      <div v-if="record" class="flex h-full flex-col">
        <header
          class="flex shrink-0 items-center justify-between border-b border-n-weak px-6 py-4"
        >
          <h2 id="opportunity-detail-title" class="m-0 text-heading-2">
            {{ t('CRM.OPPORTUNITIES.DETAIL.TITLE') }}
          </h2>
          <Button
            :aria-label="t('CRM.OPPORTUNITIES.DETAIL.CLOSE')"
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            @click="close"
          />
        </header>
        <div
          v-if="loading"
          role="status"
          class="p-6 text-label text-n-slate-11"
        >
          {{ t('CRM.OPPORTUNITIES.LOADING') }}
        </div>
        <div
          v-else-if="failed"
          role="alert"
          class="space-y-4 p-6 text-label text-n-slate-11"
        >
          <p>{{ t('CRM.OPPORTUNITIES.DETAIL.ERROR') }}</p>
          <Button
            :label="t('CRM.OPPORTUNITIES.DETAIL.RETRY')"
            variant="faded"
            @click="load"
          />
        </div>
        <div v-else class="flex-1 overflow-y-auto px-6 py-6">
          <div class="mb-6 space-y-3">
            <h3 class="m-0 break-words text-heading-1">{{ record.name }}</h3>
            <div class="flex flex-wrap items-center gap-2 text-label-small">
              <span class="rounded-md bg-n-alpha-2 px-2 py-1">{{
                stages[record.salesStage] || record.salesStage
              }}</span>
              <span
                v-if="record.important"
                class="rounded-md bg-n-amber-3 px-2 py-1 text-n-amber-11"
                >{{ t('CRM.OPPORTUNITIES.IMPORTANT') }}</span
              >
            </div>
          </div>
          <div class="mb-6 rounded-xl bg-n-alpha-1 p-4">
            <p class="mb-2 text-label-small text-n-slate-11">
              {{ t('CRM.OPPORTUNITIES.TABLE.AMOUNT') }}
            </p>
            <p class="m-0 text-heading-1 tabular-nums">
              {{
                record.amountMicros == null
                  ? '—'
                  : `${record.currency || 'CNY'} ${fmtYuan(record.amountMicros)}`
              }}
            </p>
          </div>
          <dl
            class="m-0 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-4 gap-y-5 text-label"
          >
            <dt class="text-n-slate-11">
              {{ t('CRM.OPPORTUNITIES.TABLE.OWNER') }}
            </dt>
            <dd class="m-0 flex items-center gap-2">
              <Avatar
                v-if="record.ownerName"
                :name="record.ownerName"
                :src="record.ownerAvatarUrl || ''"
                :size="24"
                rounded-full
              />
              {{ record.ownerName || '—' }}
            </dd>
            <dt class="text-n-slate-11">
              {{ t('CRM.OPPORTUNITIES.TABLE.CUSTOMER') }}
            </dt>
            <dd class="m-0 break-words">
              <button
                v-if="record.crmCustomerId && record.customerName"
                type="button"
                class="text-left underline decoration-dotted underline-offset-4 text-n-iris-11 hover:decoration-solid"
                @click="peekCustomer"
              >
                {{ record.customerName }}
              </button>
              <template v-else>{{ record.customerName || '—' }}</template>
            </dd>
            <template v-for="[key, value] in fields" :key="key">
              <dt class="text-n-slate-11">
                {{ t(`CRM.OPPORTUNITIES.${key}`) }}
              </dt>
              <dd class="m-0 break-words">{{ value || '—' }}</dd>
            </template>
          </dl>
          <section
            v-for="[key, value] in notes"
            :key="key"
            class="mt-6 border-t border-n-weak pt-5"
          >
            <h3 class="mb-3 text-heading-3">
              {{ t(`CRM.OPPORTUNITIES.${key}`) }}
            </h3>
            <p
              class="m-0 whitespace-pre-wrap break-words text-label !font-normal leading-relaxed text-n-slate-11"
            >
              {{ value }}
            </p>
          </section>
        </div>
        <footer
          class="flex shrink-0 justify-end border-t border-n-weak px-6 py-4"
        >
          <Button
            :label="t('CRM.OPPORTUNITIES.DETAIL.EDIT')"
            icon="i-lucide-pencil"
            :disabled="loading || failed"
            @click="edit"
          />
        </footer>
      </div>
    </dialog>
    <CrmCustomerPeekDialog ref="customerPeek" />
  </Teleport>
</template>
