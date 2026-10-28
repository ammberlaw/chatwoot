<script setup>
import { ref, computed, nextTick } from 'vue';
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
// 入库单/付款记录点开就地看明细，不用去 MES 或资金账户里翻。
// 明细字段 detail 接口本来就一并返回了（见 payables#detail），直接拿来渲染，不另发请求。
const drill = ref(null); // { kind: 'entry' | 'payment', data }
const drillRef = ref(null);
const openDrill = (kind, data) => {
  drill.value = { kind, data };
  nextTick(() => drillRef.value?.open());
};
const drillTitle = computed(() => {
  const d = drill.value;
  if (!d) return '';
  return d.kind === 'entry'
    ? `入库单 ${d.data.entry_no || ''}`
    : `付款记录 ${d.data.payment_no || ''}`;
});

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
        <!-- 公司主体紧挨着结算摆：财务看含税/未税时，要连带看出这是谁名下的单
             （联合触控＝未税采购订单，联迪＝含税采购合同）。 -->
        <div class="flex flex-col">
          <span class="text-xs text-n-slate-11">公司主体</span>
          <span>{{ detail.payable.bill_entity_label || '—' }}</span>
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
        <button
          v-for="e in detail.stock_entries || []"
          :key="e.entry_no"
          type="button"
          class="flex flex-wrap items-center w-full gap-x-3 px-1 py-0.5 -mx-1 text-xs text-left rounded reset-base hover:bg-n-alpha-1"
          @click="openDrill('entry', e)"
        >
          <span class="font-mono underline text-n-slate-12 underline-offset-2">
            {{ e.entry_no }}
          </span>
          <span class="text-n-slate-11">{{ e.status_label }}</span>
          <span v-if="e.posted_at" class="text-n-slate-11">
            过账 {{ day(e.posted_at) }}
          </span>
          <span v-if="e.actual_inbound_date" class="text-n-slate-11">
            到料 {{ day(e.actual_inbound_date) }}
          </span>
          <span class="text-n-slate-10">{{ (e.items || []).length }} 项</span>
        </button>
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
        <button
          v-for="(pm, i) in detail.payments || []"
          :key="`pm-${i}`"
          type="button"
          class="flex flex-wrap items-center w-full gap-x-3 px-1 py-0.5 -mx-1 text-xs text-left rounded reset-base hover:bg-n-alpha-1"
          @click="openDrill('payment', pm)"
        >
          <span class="font-mono underline text-n-slate-12 underline-offset-2">
            {{ pm.payment_no }}
          </span>
          <span class="text-n-slate-11">{{ day(pm.paid_at) }}</span>
          <span class="text-n-slate-11">{{ pm.method_label || '' }}</span>
          <span class="font-mono text-n-slate-12">
            {{ money(pm.amount_micros) }}
          </span>
          <span v-if="pm.remark" class="truncate text-n-slate-11">
            {{ pm.remark }}
          </span>
        </button>
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

    <!-- 二级弹窗：入库单收了什么 / 这笔钱从哪个户出的 -->
    <Dialog
      ref="drillRef"
      :title="drillTitle"
      width="xl"
      :show-cancel-button="false"
      :show-confirm-button="false"
    >
      <div v-if="drill" class="flex flex-col gap-4 text-sm">
        <template v-if="drill.kind === 'entry'">
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">状态</span>
              <span class="text-n-slate-12">{{ drill.data.status_label }}</span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">过账</span>
              <span class="text-n-slate-12">
                {{ day(drill.data.posted_at) || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">到料</span>
              <span class="text-n-slate-12">
                {{ day(drill.data.actual_inbound_date) || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">仓库</span>
              <span class="text-n-slate-12">
                {{ drill.data.warehouse_name || '—' }}
              </span>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <span class="text-heading-3 text-n-slate-12">
              收货明细（{{ (drill.data.items || []).length }}）
            </span>
            <div
              v-for="(it, i) in drill.data.items || []"
              :key="`it-${i}`"
              class="flex flex-wrap items-baseline gap-x-3 text-xs"
            >
              <span class="font-mono w-28 shrink-0 text-n-slate-12">
                {{ it.code || '—' }}
              </span>
              <span class="flex-1 min-w-0 truncate text-n-slate-12">
                {{ it.name || '—' }}
              </span>
              <span v-if="it.spec" class="truncate max-w-[40%] text-n-slate-10">
                {{ it.spec }}
              </span>
              <span class="tabular-nums shrink-0 text-n-slate-11">
                {{ it.qty }} {{ it.unit || '' }}
              </span>
            </div>
            <p
              v-if="!(drill.data.items || []).length"
              class="text-xs text-n-slate-11"
            >
              这张入库单没有明细行。
            </p>
          </div>

          <p v-if="drill.data.remark" class="text-xs text-n-slate-11">
            备注：{{ drill.data.remark }}
          </p>
        </template>

        <template v-else>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">付款日期</span>
              <span class="text-n-slate-12">
                {{ day(drill.data.paid_at) || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">方式</span>
              <span class="text-n-slate-12">
                {{ drill.data.method_label || '—' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">付款账户</span>
              <span class="text-n-slate-12">
                {{ drill.data.cash_account_name || '—' }}
              </span>
            </div>
            <!-- 本次核销只是这笔付款的一部分：整笔付了多少要单列，否则对不上银行流水 -->
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">本次核销</span>
              <span class="font-mono text-n-slate-12">
                {{ money(drill.data.amount_micros) }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-xs text-n-slate-10">整笔付款</span>
              <span class="font-mono text-n-slate-12">
                {{ drill.data.currency || '' }}
                {{ money(drill.data.total_amount_micros) }}
              </span>
            </div>
            <div v-if="drill.data.bank_charge_micros" class="flex flex-col">
              <span class="text-xs text-n-slate-10">手续费</span>
              <span class="font-mono text-n-slate-12">
                {{ money(drill.data.bank_charge_micros) }}
              </span>
            </div>
            <div v-if="drill.data.reference_no" class="flex flex-col">
              <span class="text-xs text-n-slate-10">银行流水号</span>
              <span class="font-mono text-n-slate-12">
                {{ drill.data.reference_no }}
              </span>
            </div>
          </div>
          <p v-if="drill.data.remark" class="text-xs text-n-slate-11">
            备注：{{ drill.data.remark }}
          </p>
        </template>
      </div>
    </Dialog>
  </Dialog>
</template>
