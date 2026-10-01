<script setup>
// 销售订单只读查看：客户详情里点订单记录用。销售订单没有对外文档模板（不像 PI / 报价单），
// 所以这里按字段分组展示，而不是复刻单据版式。不渲染成本/毛利，见下方 moneyRows。
import { ref, computed } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SalesOrdersAPI from 'dashboard/api/crm/salesOrders';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { fmtYuan } from 'dashboard/helper/crmMoney';

const props = defineProps({
  canEdit: { type: Boolean, default: false },
});
const emit = defineEmits(['edit']);

const dialogRef = ref(null);
const order = ref(null);
const loading = ref(false);

const open = async id => {
  order.value = null;
  loading.value = true;
  dialogRef.value?.open();
  try {
    const { data } = await SalesOrdersAPI.show(id);
    order.value = camelcaseKeys(data, { deep: true });
  } catch {
    useAlert('订单加载失败');
  } finally {
    loading.value = false;
  }
};
defineExpose({ open });

const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const cur = computed(() => order.value?.orderCurrency || 'USD');
const money = micros =>
  micros == null
    ? '—'
    : `${CURRENCY_SYMBOL[cur.value] || ''}${fmtYuan(micros)}`;
const date = v => (v ? String(v).slice(0, 10) : '—');
const dash = v => (v === null || v === undefined || v === '' ? '—' : v);

const STATUS_LABEL = {
  DRAFT: '草稿',
  CONFIRMED: '已确认',
  IN_PRODUCTION: '生产中',
  SHIPPED: '已出货',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
};
const KIND_LABEL = { CUSTOM: '定制生产单', STOCK: '库存出库单' };

const items = computed(() => order.value?.lineItems || []);
const baseRows = computed(() => {
  const o = order.value || {};
  return [
    ['订单号', dash(o.orderNo)],
    ['PI 号', dash(o.piNo)],
    ['订单名称', dash(o.name)],
    ['客户', dash(o.customerName)],
    ['状态', STATUS_LABEL[o.status] || dash(o.status)],
    ['类型', KIND_LABEL[o.orderKind] || dash(o.orderKind)],
    ['下单日期', date(o.orderDate)],
    ['交期', date(o.deliveryDate)],
    ['归属业务员', dash(o.ownerName)],
    ['经办人', dash(o.handledByName)],
  ];
});
// 这个弹窗是客户详情里打开的，业务天天看——只放对客户的金额。
// 成本 / 毛利 / 毛利率一概不显示（后端本来也只发给管理员/副管/财务），
// 管钱的角色要看去「销售订单」页。
const moneyRows = computed(() => {
  const o = order.value || {};
  return [
    ['订单金额', money(o.orderAmountMicros)],
    ['运费', money(o.shippingMicros)],
  ];
});
const itemMeta = li => {
  const qty = li.quantity ?? '—';
  const price = li.unitPrice ?? '—';
  return `${li.spec ? `${li.spec} · ` : ''}${qty} × ${price}`;
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    title="订单详情"
    overflow-y-auto
    :show-confirm-button="false"
    cancel-button-label="关闭"
  >
    <template #title>
      <span class="flex items-center gap-2">
        订单详情
        <span v-if="order" class="font-mono text-sm text-n-slate-11">
          {{ order.orderNo }}
        </span>
      </span>
    </template>
    <template #headerActions>
      <Button
        v-if="props.canEdit && order"
        sm
        variant="faded"
        color="slate"
        label="编辑"
        icon="i-lucide-pencil"
        @click="emit('edit', order)"
      />
    </template>

    <div v-if="loading" class="py-12 text-sm text-center text-n-slate-11">
      加载中…
    </div>
    <div v-else-if="order" class="flex flex-col gap-5">
      <div class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
        <div
          v-for="row in baseRows"
          :key="row[0]"
          class="flex gap-2 py-1 text-sm border-b border-n-weak"
        >
          <span class="w-20 shrink-0 text-n-slate-10">{{ row[0] }}</span>
          <span class="break-words text-n-slate-12">{{ row[1] }}</span>
        </div>
      </div>

      <div>
        <h4 class="mb-2 text-sm font-semibold text-n-slate-12">金额</h4>
        <div class="grid gap-x-6 gap-y-2 sm:grid-cols-2">
          <div
            v-for="row in moneyRows"
            :key="row[0]"
            class="flex gap-2 py-1 text-sm border-b border-n-weak"
          >
            <span class="w-20 shrink-0 text-n-slate-10">{{ row[0] }}</span>
            <span class="tabular-nums text-n-slate-12">{{ row[1] }}</span>
          </div>
        </div>
      </div>

      <div v-if="items.length">
        <h4 class="mb-2 text-sm font-semibold text-n-slate-12">订单明细</h4>
        <div
          v-for="(li, i) in items"
          :key="i"
          class="flex items-start justify-between gap-3 py-2 text-sm border-b border-n-weak"
        >
          <div class="min-w-0">
            <div class="font-medium truncate text-n-slate-12">
              {{ dash(li.name) }}
            </div>
            <div class="text-xs text-n-slate-10">{{ itemMeta(li) }}</div>
          </div>
          <span class="shrink-0 tabular-nums text-n-slate-12">
            {{ dash(li.amount) }}
          </span>
        </div>
      </div>

      <div v-if="order.remark">
        <h4 class="mb-1 text-sm font-semibold text-n-slate-12">备注</h4>
        <p class="text-sm whitespace-pre-wrap text-n-slate-11">
          {{ order.remark }}
        </p>
      </div>

      <div v-if="order.files?.length">
        <h4 class="mb-2 text-sm font-semibold text-n-slate-12">附件</h4>
        <a
          v-for="f in order.files"
          :key="f.id"
          :href="f.url"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center gap-2 py-1.5 text-sm text-n-iris-11 hover:underline"
        >
          <span class="i-lucide-paperclip shrink-0 size-3.5" />
          <span class="truncate">{{ f.filename }}</span>
        </a>
      </div>
    </div>
  </Dialog>
</template>
