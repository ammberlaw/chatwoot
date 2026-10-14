<script setup>
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpPayableAPI from 'dashboard/api/erp/payables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';

// 应付台账明细（财务视角）：这笔钱是哪张采购单、哪几行料、货到没到、付了几次。
// 跟应收台账点订单号弹窗同一个用法——财务核账时不想跳去 MES（多半也没有 MES 身份）。
const dialogRef = ref(null);
const detail = ref(null);
const loading = ref(false);

const PO_STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已提交',
  ORDERED: '已下单',
  RECEIVED: '已收货',
  CANCELLED: '已作废',
};
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  PENDING_MANAGER: '待部门主管',
  PENDING_GM: '待审批',
  APPROVED: '已通过',
  REJECTED: '已驳回',
};

const money = micros =>
  micros === null || micros === undefined ? '—' : fmtMoney(micros);
const num = v => (v === null || v === undefined || v === '' ? '—' : v);
const day = v => (v ? String(v).slice(0, 10) : '—');

const open = async payableId => {
  if (!payableId) return;
  detail.value = null;
  loading.value = true;
  dialogRef.value?.open();
  try {
    const { data } = await ErpPayableAPI.detail(payableId);
    detail.value = data.payload;
  } catch {
    useAlert('台账明细取不到，可能已被删除');
    dialogRef.value?.close();
  } finally {
    loading.value = false;
  }
};
const close = () => dialogRef.value?.close();
defineExpose({ open, close });
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
    title="应付台账明细"
  >
    <div v-if="loading" class="py-10 text-center text-n-slate-11">加载中…</div>
    <div v-else-if="detail" class="flex flex-col gap-5">
      <!-- 抬头 -->
      <div
        class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4 text-n-slate-12"
      >
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">台账单号</span>
          <span class="font-mono">{{ detail.payable.payable_no }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">供应商</span>
          <span>{{ detail.payable.supplier_name || '—' }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">采购单</span>
          <span class="font-mono">
            {{ detail.purchase_order?.supplier_po_no || '—' }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">状态</span>
          <span>{{ detail.payable.status_label }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">应付</span>
          <span class="font-mono">
            {{ detail.payable.currency }}
            {{ money(detail.payable.total_amount_micros) }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">已付</span>
          <span class="font-mono">
            {{ money(detail.payable.paid_amount_micros) }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">未付</span>
          <span class="font-mono text-n-slate-12">
            {{ money(detail.payable.outstanding_micros) }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">结算</span>
          <span>{{ detail.payable.settle_type_label }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">发生日期</span>
          <span>{{ day(detail.payable.incurred_on) }}</span>
        </div>
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">到期日</span>
          <span>{{ day(detail.payable.due_date) }}</span>
        </div>
        <div v-if="detail.purchase_order" class="flex flex-col">
          <span class="text-xs text-n-slate-11">采购单状态</span>
          <span>
            {{
              PO_STATUS_LABELS[detail.purchase_order.status] ||
              detail.purchase_order.status
            }}
            ·
            {{
              APPROVAL_LABELS[detail.purchase_order.approval_status] ||
              detail.purchase_order.approval_status
            }}
          </span>
        </div>
        <div
          v-if="detail.purchase_order?.production_order_no"
          class="flex flex-col"
        >
          <span class="text-xs text-n-slate-11">来源销售订单</span>
          <span class="font-mono">
            {{ detail.purchase_order.production_order_no }}
          </span>
        </div>
      </div>

      <!-- 买了什么：只列这家供应商在这张采购单上的行 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          采购明细（{{ (detail.items || []).length }} 行）
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
                  已收
                </th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">单位</th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  单价
                </th>
                <th class="px-2 py-2 font-medium text-right whitespace-nowrap">
                  金额
                </th>
                <th class="px-2 py-2 font-medium whitespace-nowrap">备注</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(item, i) in detail.items || []"
                :key="`pi-${i}`"
                class="border-b border-n-weak align-top"
              >
                <td
                  class="px-2 py-2 font-mono text-xs whitespace-nowrap text-n-slate-11"
                >
                  {{ item.code || '—' }}
                </td>
                <td class="px-2 py-2 text-n-slate-12">
                  {{ item.name || '—' }}
                </td>
                <td
                  class="px-2 py-2 text-xs text-n-slate-11 max-w-md whitespace-pre-wrap"
                >
                  {{ item.spec || '—' }}
                </td>
                <td class="px-2 py-2 font-mono text-right">
                  {{ num(item.quantity) }}
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-11">
                  {{ num(item.received_qty) }}
                </td>
                <td class="px-2 py-2 text-n-slate-11">{{ item.unit || '' }}</td>
                <td class="px-2 py-2 font-mono text-right">
                  {{ money(item.unit_price_micros) }}
                </td>
                <td class="px-2 py-2 font-mono text-right text-n-slate-12">
                  {{ money(item.amount_micros) }}
                </td>
                <td class="px-2 py-2 text-xs text-n-slate-11">
                  {{ item.remark || '' }}
                </td>
              </tr>
              <tr v-if="!(detail.items || []).length">
                <td colspan="9" class="px-2 py-6 text-center text-n-slate-11">
                  这笔应付没有对上采购明细行（手工建的台账，或采购行上没挂这家供应商）。
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- 货到没到 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          入库单（{{ (detail.stock_entries || []).length }}）
        </span>
        <div
          v-for="e in detail.stock_entries || []"
          :key="e.entry_no"
          class="flex flex-wrap items-center gap-x-3 text-xs"
        >
          <span class="font-mono text-n-slate-12">{{ e.entry_no }}</span>
          <span class="text-n-slate-11">{{ e.status_label }}</span>
          <span v-if="e.posted_at" class="text-n-slate-11">
            过账 {{ day(e.posted_at) }}
          </span>
          <span v-if="e.actual_inbound_date" class="text-n-slate-11">
            到料 {{ day(e.actual_inbound_date) }}
          </span>
        </div>
        <p
          v-if="!(detail.stock_entries || []).length"
          class="text-sm text-n-slate-11"
        >
          这张采购单还没有入库单。
        </p>
      </div>

      <!-- 付了几次 -->
      <div class="flex flex-col gap-2">
        <span class="text-heading-3 text-n-slate-12">
          付款记录（{{ (detail.payments || []).length }}）
        </span>
        <div
          v-for="(pm, i) in detail.payments || []"
          :key="`pm-${i}`"
          class="flex flex-wrap items-center gap-x-3 text-xs"
        >
          <span class="font-mono text-n-slate-12">{{ pm.payment_no }}</span>
          <span class="text-n-slate-11">{{ day(pm.paid_at) }}</span>
          <span class="text-n-slate-11">{{ pm.method_label || '' }}</span>
          <span class="font-mono text-n-slate-12">
            {{ money(pm.amount_micros) }}
          </span>
          <span v-if="pm.remark" class="text-n-slate-11">{{ pm.remark }}</span>
        </div>
        <p
          v-if="!(detail.payments || []).length"
          class="text-sm text-n-slate-11"
        >
          还没有付过款。
        </p>
      </div>

      <p v-if="detail.payable.remark" class="text-xs text-n-slate-11">
        台账备注：{{ detail.payable.remark }}
      </p>
      <p
        v-if="detail.purchase_order?.internal_remark"
        class="text-xs text-n-slate-11"
      >
        采购对内备注：{{ detail.purchase_order.internal_remark }}
      </p>
    </div>
  </Dialog>
</template>
