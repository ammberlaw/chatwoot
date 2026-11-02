<script setup>
import { ref, computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpReceivableAPI from 'dashboard/api/erp/receivables';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 销售订单详情（财务视角）：出了什么货、什么价、挂了哪些 MES 单据。
//
// 抽成共享件给应收台账和成本毛利两处用——这屏 200 多行，复制一份过去迟早两边长歪。
// 走 ERP 侧接口而不是 CRM 的：财务多半没有 crm_role，CRM 那套会 403。

const dialogRef = ref(null);
const orderDetail = ref(null);
const orderLoading = ref(false);

const SO_STATUS_LABELS = {
  DRAFT: '草稿',
  CONFIRMED: '已确认',
  IN_PRODUCTION: '生产中',
  SHIPPED: '已出货',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
};
const PO_STATUS_LABELS = {
  DRAFT: '草稿',
  IN_PROGRESS: '进行中',
  COMPLETED: '已完结',
  CANCELLED: '已取消',
};

const money = micros => (micros ? fmtMoney(micros) : '—');

const ORDER_KIND_LABELS = { CUSTOM: '定制单', STOCK: '库存单' };
const orderKindLabel = computed(
  () => ORDER_KIND_LABELS[orderDetail.value?.order?.order_kind] || ''
);

// 外币单折本位币：汇率后端一直在传。本位币单（CNY 或汇率 1）不重复印一遍。
const baseAmount = computed(() => {
  const o = orderDetail.value?.order;
  const rate = Number(o?.exchange_rate);
  if (!o?.amount_micros || !rate || rate === 1) return '';
  return fmtMoney(Math.round(o.amount_micros * rate));
});

const outstandingMicros = computed(() => {
  const r = orderDetail.value?.receivable;
  if (!r) return 0;
  return Math.max(
    (r.total_amount_micros || 0) - (r.received_amount_micros || 0),
    0
  );
});

// 本次比上次贵标红、便宜标绿。首次采购没有可比的，不着色。
const priceClass = lp => {
  if (!lp.rate_micros || !lp.this_rate_micros) return 'text-n-slate-11';
  if (lp.this_rate_micros > lp.rate_micros) return 'text-n-ruby-11';
  if (lp.this_rate_micros < lp.rate_micros) return 'text-n-teal-11';
  return 'text-n-slate-11';
};
// 运费这类行没有数量和单价、只有金额，照原样显示别补 0。
const num = v => (v === null || v === undefined || v === '' ? '—' : v);
// 订单明细里的金额是**原币面值**（不是 micros），直接按两位小数排版。
const plainMoney = v =>
  v === null || v === undefined || v === ''
    ? '—'
    : Number(v).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });

// 付款方式存的是 code（BANK_TRANSFER / ALIBABA …），中文名在「分组/来源设置」里配，
// 原来直接把 code 印给财务看。ensureLoaded 只拉分组和来源，payment_term 要单独取。
const { load: loadCrmOptions, paymentTermLabel } = useCrmOptions();
const paymentTermText = computed(() => {
  const code = orderDetail.value?.order?.payment_term;
  return code ? paymentTermLabel(code) || code : '';
});

const open = async orderId => {
  if (!orderId) return;
  orderDetail.value = null;
  orderLoading.value = true;
  dialogRef.value?.open();
  loadCrmOptions('payment_term');
  try {
    const { data } = await ErpReceivableAPI.orderDetail(orderId);
    orderDetail.value = data.payload;
  } catch {
    useAlert('订单详情取不到，可能已被删除');
    dialogRef.value?.close();
  } finally {
    orderLoading.value = false;
  }
};
const close = () => dialogRef.value?.close();
defineExpose({ open, close });

// 点单号就地弹窗看，不再跳去 MES。
//
// 财务在应收/成本毛利上核一张订单时，关联的生产订单和出货单只是「顺手确认一眼」，
// 跳去 MES 等于丢掉当前这张单的上下文、看完还得找回来；而且财务多半没有 MES 身份，
// 跳过去不少页是空的。详情所需的字段（阶段流转、出入库单、出了什么货）order_detail
// 接口本来就一并返回了，直接拿来渲染，不另发请求。
// 弹窗里就是完整明细：阶段流转、出入库单、BOM 用量、报工、质检都在，不再留「去 MES」的
// 出口——留着反而像在说「这里看不全」，而财务多半也进不去 MES。
const drill = ref(null); // { kind: 'po' | 'shipment', data }
const drillRef = ref(null);
const openDrill = (kind, data) => {
  drill.value = { kind, data };
  nextTick(() => drillRef.value?.open());
};

const drillTitle = computed(() => {
  const d = drill.value;
  if (!d) return '';
  return d.kind === 'po'
    ? `生产订单 ${d.data.order_no || ''}`
    : `出货单 ${d.data.shipment_no || ''}`;
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :dismissible="false"
    width="4xl"
    overflow-y-auto
    :show-confirm-button="false"
    show-cancel-button
    cancel-button-label="关闭"
    title="销售订单详情"
  >
    <div v-if="orderLoading" class="py-10 text-center text-n-slate-11">
      加载中…
    </div>
    <div v-else-if="orderDetail" class="flex flex-col gap-5">
      <!-- 抬头 -->
      <div
        class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4 text-n-slate-12"
      >
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">订单号</span>
          <span class="font-mono">{{ orderDetail.order.order_no }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">客户</span>
          <span>{{ orderDetail.order.customer_name || '—' }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">业务员</span>
          <span>{{ orderDetail.order.owner_name || '—' }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">状态</span>
          <span>{{
            SO_STATUS_LABELS[orderDetail.order.status] ||
            orderDetail.order.status
          }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">下单日期</span>
          <span>{{ (orderDetail.order.order_date || '—').slice(0, 10) }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">交期</span>
          <span>{{
            (orderDetail.order.delivery_date || '—').slice(0, 10)
          }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">PI 编号</span>
          <span class="font-mono">{{ orderDetail.order.pi_no || '—' }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">订单金额</span>
          <span class="font-mono">
            {{ orderDetail.order.currency || 'CNY' }}
            {{ money(orderDetail.order.amount_micros) }}
          </span>
          <!-- 外币单只给原币，财务对不出这单值多少钱。汇率后端一直在传，补上折算。
               本位币单（CNY，汇率 1）不重复印一遍。 -->
          <span v-if="baseAmount" class="font-mono text-xs text-n-slate-11">
            ≈ CNY {{ baseAmount }}（汇率 {{ orderDetail.order.exchange_rate }}）
          </span>
        </div>
        <!-- 运费是向客户另收的钱，订单金额里不含它——不单列出来，财务就对不上
           建账金额，也看不出这单到底该收客户多少。 -->
        <div v-if="orderDetail.order.shipping_micros" class="flex flex-col">
          <span class="text-xs text-n-slate-11">运费</span>
          <span class="font-mono">
            {{ orderDetail.order.currency || 'CNY' }}
            {{ money(orderDetail.order.shipping_micros) }}
          </span>
        </div>
        <div v-if="orderKindLabel" class="flex flex-col">
          <span class="text-xs text-n-slate-11">订单类型</span>
          <span>{{ orderKindLabel }}</span>
        </div>
        <div v-if="orderDetail.order.opportunity_name" class="flex flex-col">
          <span class="text-xs text-n-slate-11">来源商机</span>
          <span>{{ orderDetail.order.opportunity_name }}</span>
        </div>
        <div v-if="paymentTermText" class="flex flex-col">
          <span class="text-xs text-n-slate-11">付款方式</span>
          <span>{{ paymentTermText }}</span>
        </div>
        <div v-if="orderDetail.receivable" class="flex flex-col">
          <span class="text-xs text-n-slate-11">已建应收</span>
          <span class="font-mono">{{
            orderDetail.receivable.receivable_no
          }}</span>
          <!-- 从应收台账点进来的人，第一个要知道的就是收了多少、还差多少。 -->
          <span class="font-mono text-xs text-n-slate-11">
            已收
            {{ fmtMoney(orderDetail.receivable.received_amount_micros || 0) }} ·
            未收 {{ fmtMoney(outstandingMicros) }}
          </span>
        </div>
      </div>

      <!-- 订单明细：出了什么货、单价多少 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          订单明细（{{ (orderDetail.line_items || []).length }} 行）
        </span>
        <HScrollButtons />
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr
                class="text-left border-b text-n-slate-11 border-n-weak whitespace-nowrap"
              >
                <th class="px-2 py-2 font-medium whitespace-nowrap">编码</th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">品名</th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">规格</th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  数量
                </th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  单价
                </th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  金额
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(item, i) in orderDetail.line_items || []"
                :key="`li-${i}`"
                class="border-b border-n-weak align-top"
              >
                <td
                  class="px-2 py-2 font-mono text-xs whitespace-nowrap text-n-slate-11"
                >
                  {{ item.sku || '—' }}
                </td>
                <td class="px-2 py-2 text-n-slate-12">{{ item.name }}</td>
                <td
                  class="px-2 py-2 text-xs text-n-slate-11 max-w-md whitespace-pre-wrap"
                >
                  {{ item.spec || '—' }}
                </td>
                <td class="px-2 py-2 font-mono text-right">
                  {{ num(item.quantity) }}
                </td>
                <td class="px-2 py-2 font-mono text-right">
                  {{ plainMoney(item.unit_price) }}
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ plainMoney(item.amount) }}
                </td>
              </tr>
              <tr v-if="!(orderDetail.line_items || []).length">
                <td colspan="6" class="px-2 py-6 text-center text-n-slate-11">
                  这张订单没有录明细行。
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- 关联 MES：生产订单 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          关联生产订单（{{ (orderDetail.production_orders || []).length }}）
        </span>
        <div
          v-for="po in orderDetail.production_orders || []"
          :key="po.order_no"
          class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-x-3 text-sm">
            <button
              type="button"
              class="font-mono underline text-n-iris-11 underline-offset-2 hover:opacity-80"
              title="点开看这张生产订单"
              @click="openDrill('po', po)"
            >
              {{ po.order_no }}
            </button>
            <span class="text-n-slate-12">{{ po.product_name }}</span>
            <span class="text-n-slate-11">
              {{ po.qty }} {{ po.unit || '' }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ po.stage_label }} ·
              {{ PO_STATUS_LABELS[po.status] || po.status }}
            </span>
          </div>
          <div
            v-if="(po.stock_entries || []).length"
            class="flex flex-wrap gap-x-4 text-xs text-n-slate-11"
          >
            <span
              v-for="e in po.stock_entries"
              :key="e.entry_no"
              class="font-mono"
            >
              {{ e.purpose_label }} {{ e.entry_no }}（{{ e.status_label }}）
            </span>
          </div>
        </div>
        <p
          v-if="!(orderDetail.production_orders || []).length"
          class="text-sm text-n-slate-11"
        >
          这张销售订单没有挂生产订单（外购/现货单，或还没转生产）。
        </p>
      </div>

      <!-- 采购：这单买了什么、跟谁买、花了多少。
           只在 ERP 的详情里出现——CRM 侧走另一个接口，一个采购字段都没有
           （销售端不可见成本，见 Erp::OrderPurchaseTrace 的说明）。 -->
      <div
        v-if="(orderDetail.purchase?.purchase_orders || []).length"
        class="flex flex-col gap-2"
      >
        <span class="text-heading-3 text-n-slate-12">
          采购单（{{ orderDetail.purchase.purchase_orders.length }}）
        </span>
        <div
          v-for="po in orderDetail.purchase.purchase_orders"
          :key="po.po_no"
          class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-sm text-n-slate-12">{{ po.po_no }}</span>
            <span class="text-xs text-n-slate-10">{{ po.suppliers.join('、') || '—' }}</span>
            <span class="font-mono text-sm text-n-slate-12">
              {{ money(po.total_amount_micros) }}
            </span>
            <!-- 合并采购：这张单还给别的生产订单买了料，金额不全属于本单。
                 不标出来，财务会把别单的钱算进这单成本。 -->
            <span
              v-if="po.shared_with_others"
              class="px-1.5 py-0.5 rounded text-[11px] bg-n-amber-3 text-n-amber-11"
              title="这张采购单还给别的生产订单买了料，金额不全属于本单"
            >
              合并采购
            </span>
          </div>
          <div
            v-for="(it, i) in po.items"
            :key="`${po.po_no}-${i}`"
            class="text-xs text-n-slate-11"
          >
            {{ it.code || '—' }} {{ it.name }} ×{{ it.qty }}{{ it.unit || '' }}
            · 单价 {{ money(it.rate_micros) }}
            · {{ money(it.amount_micros) }}
            <span v-if="it.supplier_name" class="text-n-slate-10">
              · {{ it.supplier_name }}
            </span>
          </div>
        </div>

        <!-- 最近一次采购单价：不一定来自本单，用来判断这次买贵了还是便宜了。 -->
        <template v-if="(orderDetail.purchase?.last_prices || []).length">
          <span class="mt-1 text-label-small text-n-slate-11">
            最近一次采购单价（对比）
          </span>
          <div class="overflow-x-auto">
            <table class="w-full text-xs">
              <thead>
                <tr class="text-left border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-1 font-medium">物料</th>
                  <th class="px-2 py-1 font-medium text-right">本次</th>
                  <th class="px-2 py-1 font-medium text-right">上次</th>
                  <th class="px-2 py-1 font-medium">上次供应商 / 单号</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(lp, i) in orderDetail.purchase.last_prices"
                  :key="`lp-${i}`"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1 text-n-slate-12">
                    {{ lp.code || '—' }} {{ lp.name }}
                  </td>
                  <td class="px-2 py-1 font-mono text-right text-n-slate-12">
                    {{ money(lp.this_rate_micros) }}
                  </td>
                  <td
                    class="px-2 py-1 font-mono text-right"
                    :class="priceClass(lp)"
                  >
                    {{ lp.rate_micros ? money(lp.rate_micros) : '首次采购' }}
                  </td>
                  <td class="px-2 py-1 text-n-slate-10">
                    {{ lp.rate_micros ? `${lp.supplier_name || '—'} / ${lp.po_no || '—'}` : '—' }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>

      <!-- 关联 MES：出货单 —— 实际出了什么货 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          出货记录（{{ (orderDetail.shipments || []).length }}）
        </span>
        <div
          v-for="sp in orderDetail.shipments || []"
          :key="sp.shipment_no"
          class="flex flex-col gap-1 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-x-3 text-sm">
            <button
              type="button"
              class="font-mono underline text-n-iris-11 underline-offset-2 hover:opacity-80"
              title="点开看这张出货单"
              @click="openDrill('shipment', sp)"
            >
              {{ sp.shipment_no }}
            </button>
            <span class="text-n-slate-11">{{ sp.kind_label }}</span>
            <span class="text-n-slate-11">{{ sp.status_label }}</span>
            <span v-if="sp.warehouse" class="text-xs text-n-slate-11">
              {{ sp.warehouse }}
            </span>
            <span v-if="sp.shipped_at" class="text-xs text-n-slate-11">
              出库 {{ (sp.shipped_at || '').slice(0, 10) }}
            </span>
          </div>
          <div
            v-for="(it, i) in sp.items || []"
            :key="`si-${i}`"
            class="flex flex-wrap gap-x-3 text-xs text-n-slate-11"
          >
            <span class="text-n-slate-12">{{ it.product_name || '—' }}</span>
            <span v-if="it.product_sku" class="font-mono">{{
              it.product_sku
            }}</span>
            <span class="font-mono">{{ it.qty }} {{ it.unit || '' }}</span>
            <span v-if="it.remark">{{ it.remark }}</span>
          </div>
        </div>
        <p
          v-if="!(orderDetail.shipments || []).length"
          class="text-sm text-n-slate-11"
        >
          还没有出货单。
        </p>
      </div>

      <p v-if="orderDetail.order.remark" class="text-xs text-n-slate-11">
        订单备注：{{ orderDetail.order.remark }}
      </p>
    </div>

    <!-- 钻取层：生产订单 / 出货单就地看。原生 <dialog> 可以叠，后开的在顶层。 -->
    <Dialog
      ref="drillRef"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="drillTitle"
    >
      <div v-if="drill" class="flex flex-col gap-4 text-sm">
        <!-- 生产订单 -->
        <template v-if="drill.kind === 'po'">
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">成品</span>
              <span class="text-n-slate-12">
                {{ drill.data.product_name || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">产成品代码</span>
              <span class="font-mono text-n-slate-12">
                {{ drill.data.product_code || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">数量</span>
              <span class="text-n-slate-12">
                {{ drill.data.qty }} {{ drill.data.unit || '' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">当前阶段 / 状态</span>
              <span class="text-n-slate-12">
                {{ drill.data.stage_label }} ·
                {{ PO_STATUS_LABELS[drill.data.status] || drill.data.status }}
              </span>
            </div>
          </div>

          <!-- 阶段流转：财务核的就是「走到哪一步了、什么时候走的」 -->
          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">阶段流转</span>
            <div
              v-for="st in drill.data.stages || []"
              :key="st.stage"
              class="flex flex-wrap items-center gap-x-3 text-xs"
            >
              <span class="w-20 text-n-slate-12">{{ st.label }}</span>
              <span class="text-n-slate-11">
                进入 {{ (st.entered_at || '').slice(0, 10) || '—' }}
              </span>
              <span v-if="st.acked_at" class="text-n-slate-11">
                接单 {{ (st.acked_at || '').slice(0, 10) }}
              </span>
            </div>
            <p
              v-if="!(drill.data.stages || []).length"
              class="text-xs text-n-slate-11"
            >
              还没有阶段记录。
            </p>
          </div>

          <!-- 出入库单：领料/入库都在这里，不用再去 MES 翻 -->
          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              出入库单（{{ (drill.data.stock_entries || []).length }}）
            </span>
            <div
              v-for="e in drill.data.stock_entries || []"
              :key="e.entry_no"
              class="flex flex-wrap items-center gap-x-3 text-xs"
            >
              <span class="font-mono text-n-slate-12">{{ e.entry_no }}</span>
              <span class="text-n-slate-11">{{ e.purpose_label }}</span>
              <span class="text-n-slate-11">{{ e.status_label }}</span>
              <span v-if="e.from_warehouse" class="text-n-slate-11">
                出 {{ e.from_warehouse }}
              </span>
              <span v-if="e.to_warehouse" class="text-n-slate-11">
                入 {{ e.to_warehouse }}
              </span>
              <span v-if="e.posted_at" class="text-n-slate-11">
                过账 {{ (e.posted_at || '').slice(0, 10) }}
              </span>
            </div>
            <p
              v-if="!(drill.data.stock_entries || []).length"
              class="text-xs text-n-slate-11"
            >
              这张生产订单还没有出入库单。
            </p>
          </div>

          <!-- BOM 用量：这单要用哪些料、各多少。只给料号/品名/规格/用量——
               单价和金额不下发（销售端不可见成本，见 SalesOrderTraceService#bom_json）。 -->
          <div v-if="drill.data.bom" class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              生产任务单 {{ drill.data.bom.bom_no }}（{{
                (drill.data.bom.items || []).length
              }}
              行 · 基准 {{ drill.data.bom.base_qty }}）
            </span>
            <div
              v-for="(it, i) in drill.data.bom.items || []"
              :key="`${it.material_no}-${i}`"
              class="flex flex-wrap items-baseline gap-x-3 text-xs"
            >
              <span class="font-mono w-28 shrink-0 text-n-slate-12">
                {{ it.material_no || '—' }}
              </span>
              <span class="flex-1 min-w-0 truncate text-n-slate-12">
                {{ it.name || '—' }}
              </span>
              <span v-if="it.spec" class="text-n-slate-10 truncate max-w-[40%]">
                {{ it.spec }}
              </span>
              <span class="tabular-nums shrink-0 text-n-slate-11">
                {{ it.qty }} {{ it.unit || '' }}
              </span>
            </div>
          </div>

          <!-- 报工：做了多少、谁做的、废了多少 -->
          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              生产报工（{{ (drill.data.records || []).length }}）
            </span>
            <div
              v-for="(r, i) in drill.data.records || []"
              :key="`rec-${i}`"
              class="flex flex-wrap items-center gap-x-3 text-xs"
            >
              <span class="w-20 shrink-0 text-n-slate-12">
                {{ r.operation_name || '—' }}
              </span>
              <span class="text-n-slate-11"> 完工 {{ r.qty_completed }} </span>
              <span v-if="r.qty_scrap" class="text-n-ruby-11">
                报废 {{ r.qty_scrap }}
              </span>
              <span v-if="r.operator_name" class="text-n-slate-11">
                {{ r.operator_name }}
              </span>
              <span class="text-n-slate-10">
                {{ (r.recorded_at || '').slice(0, 10) }}
              </span>
            </div>
            <p
              v-if="!(drill.data.records || []).length"
              class="text-xs text-n-slate-11"
            >
              还没有报工记录。
            </p>
          </div>

          <!-- 质检：合格多少、要不要返工 -->
          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              质量检验（{{ (drill.data.inspections || []).length }}）
            </span>
            <div
              v-for="(q, i) in drill.data.inspections || []"
              :key="`insp-${i}`"
              class="flex flex-wrap items-center gap-x-3 text-xs"
            >
              <span class="w-14 shrink-0 text-n-slate-12">{{ q.kind }}</span>
              <span
                :class="
                  q.result === 'PASS' ? 'text-n-teal-11' : 'text-n-ruby-11'
                "
              >
                {{ q.result === 'PASS' ? '合格' : q.result }}
              </span>
              <span class="text-n-slate-11">
                检 {{ q.inspected_qty }} / 合格 {{ q.passed_qty }}
              </span>
              <span v-if="q.failed_qty" class="text-n-ruby-11">
                不良 {{ q.failed_qty }}
              </span>
              <span v-if="q.need_rework" class="text-n-amber-11">需返工</span>
              <span v-if="q.defect_reason" class="truncate text-n-slate-10">
                {{ q.defect_reason }}
              </span>
              <span class="text-n-slate-10">
                {{ (q.inspected_at || '').slice(0, 10) }}
              </span>
            </div>
            <p
              v-if="!(drill.data.inspections || []).length"
              class="text-xs text-n-slate-11"
            >
              还没有质检记录。
            </p>
          </div>
        </template>

        <!-- 出货单 -->
        <template v-else>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">类型</span>
              <span class="text-n-slate-12">{{ drill.data.kind_label }}</span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">状态</span>
              <span class="text-n-slate-12">{{ drill.data.status_label }}</span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">发货仓</span>
              <span class="text-n-slate-12">
                {{ drill.data.warehouse || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">关联生产订单</span>
              <span class="font-mono text-n-slate-12">
                {{ drill.data.production_order_no || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">提交 / 审核 / 出库</span>
              <span class="text-xs text-n-slate-11">
                {{ (drill.data.submitted_at || '').slice(0, 10) || '—' }} /
                {{ (drill.data.approved_at || '').slice(0, 10) || '—' }} /
                {{ (drill.data.shipped_at || '').slice(0, 10) || '—' }}
              </span>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              出了什么货（{{ (drill.data.items || []).length }}）
            </span>
            <table class="w-full text-xs">
              <thead>
                <tr class="text-left border-b text-n-slate-11 border-n-weak">
                  <th class="px-2 py-1 font-medium whitespace-nowrap">编码</th>
                  <th class="px-2 py-1 font-medium">品名</th>
                  <th
                    class="px-2 py-1 font-medium text-right whitespace-nowrap"
                  >
                    数量
                  </th>
                  <th class="px-2 py-1 font-medium whitespace-nowrap">单位</th>
                  <th class="px-2 py-1 font-medium">备注</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(it, i) in drill.data.items || []"
                  :key="`d-${i}`"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-1 font-mono text-n-slate-11">
                    {{ it.product_sku || '—' }}
                  </td>
                  <td class="px-2 py-1 text-n-slate-12">
                    {{ it.product_name || '—' }}
                  </td>
                  <td class="px-2 py-1 font-mono text-right text-n-slate-12">
                    {{ it.qty }}
                  </td>
                  <td class="px-2 py-1 text-n-slate-11">{{ it.unit || '' }}</td>
                  <td class="px-2 py-1 text-n-slate-11">
                    {{ it.remark || '' }}
                  </td>
                </tr>
                <tr v-if="!(drill.data.items || []).length">
                  <td colspan="5" class="px-2 py-4 text-center text-n-slate-11">
                    这张出货单没有明细。
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>
    </Dialog>
  </Dialog>
</template>
