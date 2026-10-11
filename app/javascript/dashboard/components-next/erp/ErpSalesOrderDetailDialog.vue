<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpReceivableAPI from 'dashboard/api/erp/receivables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 销售订单详情（财务视角）：出了什么货、什么价、挂了哪些 MES 单据。
//
// 抽成共享件给应收台账和成本毛利两处用——这屏 200 多行，复制一份过去迟早两边长歪。
// 走 ERP 侧接口而不是 CRM 的：财务多半没有 crm_role，CRM 那套会 403。
const { accountId } = useAccount();
const router = useRouter();

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

const open = async orderId => {
  if (!orderId) return;
  orderDetail.value = null;
  orderLoading.value = true;
  dialogRef.value?.open();
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

// 点单号跳到 MES 对应页面。跳之前先关弹窗，否则回退回来会看到一个盖着的空壳。
// 生产订单页认 ?q=<单号>（列表按它收窄）；出库页认 ?focus=<id>（直接展开那张单）。
const goProductionOrder = po => {
  if (!po?.order_no) return;
  close();
  router.push({
    name: 'mes_production_orders_index',
    params: { accountId: accountId.value },
    query: { q: po.order_no },
  });
};
const goShipment = sp => {
  if (!sp?.id) return;
  close();
  router.push({
    name: 'mes_shipments_index',
    params: { accountId: accountId.value },
    query: { focus: String(sp.id) },
  });
};
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
        <div v-if="orderDetail.order.opportunity_name" class="flex flex-col">
          <span class="text-xs text-n-slate-11">来源商机</span>
          <span>{{ orderDetail.order.opportunity_name }}</span>
        </div>
        <div v-if="orderDetail.order.payment_term" class="flex flex-col">
          <span class="text-xs text-n-slate-11">付款方式</span>
          <span>{{ orderDetail.order.payment_term }}</span>
        </div>
        <div v-if="orderDetail.receivable" class="flex flex-col">
          <span class="text-xs text-n-slate-11">已建应收</span>
          <span class="font-mono">{{
            orderDetail.receivable.receivable_no
          }}</span>
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
              title="去生产订单页看这一单"
              @click="goProductionOrder(po)"
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
              title="去销售出库页打开这张单"
              @click="goShipment(sp)"
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
  </Dialog>
</template>
