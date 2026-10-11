<script setup>
import { computed } from 'vue';
import { fmtMoney, rmbCapital } from 'dashboard/helper/erpMoney';

// 收款单 / 付款单票面（两者同构，用 kind 区分抬头与往来单位称谓）。
// 与凭证票面同一套打印栈（printElement），版式：抬头 + 单号/日期 + 往来单位 + 金额与大写
// + 核销明细 + 签字栏。
const props = defineProps({
  record: { type: Object, required: true },
  kind: { type: String, default: 'receipt' }, // receipt 收款单 / payment 付款单
});

const isReceipt = computed(() => props.kind === 'receipt');
const title = computed(() => (isReceipt.value ? '收 款 单' : '付 款 单'));
const partyLabel = computed(() =>
  isReceipt.value ? '付款客户' : '收款供应商'
);
const partyName = computed(() =>
  isReceipt.value ? props.record.customer_name : props.record.supplier_name
);
const docNo = computed(() =>
  isReceipt.value ? props.record.receipt_no : props.record.payment_no
);
const docDate = computed(() =>
  isReceipt.value ? props.record.received_at : props.record.paid_at
);
const allocations = computed(() => props.record.allocations || []);
const capital = computed(() => rmbCapital(props.record.amount_micros));
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- 票面必须内联样式：printElement 只把白名单计算样式内联进克隆，列宽等靠 class 会在打印时丢。 -->
<template>
  <div
    class="erp-print-sheet"
    style="
      width: 100%;
      padding: 10px 4px 18px;
      color: #111;
      font-family: 'Songti SC', 'SimSun', serif;
      page-break-after: always;
    "
  >
    <div
      style="
        text-align: center;
        font-size: 20px;
        letter-spacing: 8px;
        font-weight: 700;
      "
    >
      {{ title }}
    </div>

    <div
      style="
        display: flex;
        justify-content: space-between;
        font-size: 12px;
        margin: 10px 2px 6px;
      "
    >
      <span>日期：{{ docDate }}</span>
      <span>单号：{{ docNo }}</span>
      <span>水单号：{{ record.reference_no || '—' }}</span>
    </div>

    <table
      style="
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        table-layout: fixed;
      "
    >
      <tbody>
        <tr>
          <td style="border: 1px solid #333; padding: 6px; width: 22%">
            {{ partyLabel }}
          </td>
          <td style="border: 1px solid #333; padding: 6px" colspan="3">
            {{ partyName }}
          </td>
        </tr>
        <tr>
          <td style="border: 1px solid #333; padding: 6px">收付方式</td>
          <td style="border: 1px solid #333; padding: 6px; width: 28%">
            {{ record.method_label }}
          </td>
          <td style="border: 1px solid #333; padding: 6px; width: 22%">
            币种 / 汇率
          </td>
          <td style="border: 1px solid #333; padding: 6px">
            {{ record.currency }} / {{ Number(record.exchange_rate) }}
          </td>
        </tr>
        <tr>
          <td style="border: 1px solid #333; padding: 6px">金额（大写）</td>
          <td style="border: 1px solid #333; padding: 6px" colspan="2">
            {{ capital }}
          </td>
          <td
            style="
              border: 1px solid #333;
              padding: 6px;
              text-align: right;
              font-weight: 700;
            "
          >
            {{ record.currency }} {{ fmtMoney(record.amount_micros) }}
          </td>
        </tr>
        <tr v-if="record.bank_charge_micros">
          <td style="border: 1px solid #333; padding: 6px">银行手续费</td>
          <td style="border: 1px solid #333; padding: 6px" colspan="3">
            {{ fmtMoney(record.bank_charge_micros) }}
          </td>
        </tr>
      </tbody>
    </table>

    <div style="font-size: 12px; margin: 10px 2px 4px">核销明细</div>
    <table
      style="
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        table-layout: fixed;
      "
    >
      <thead>
        <tr>
          <th
            class="whitespace-nowrap"
            style="border: 1px solid #333; padding: 5px; width: 40%"
          >
            台账单号
          </th>
          <th
            class="whitespace-nowrap"
            style="border: 1px solid #333; padding: 5px"
          >
            核销金额
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="allocation in allocations" :key="allocation.id">
          <td style="border: 1px solid #333; padding: 5px">
            {{ allocation.receivable_no || allocation.payable_no }}
          </td>
          <td style="border: 1px solid #333; padding: 5px; text-align: right">
            {{ fmtMoney(allocation.amount_micros) }}
          </td>
        </tr>
        <tr v-if="!allocations.length">
          <td style="border: 1px solid #333; padding: 5px" colspan="2">
            未核销（预收/预付挂账）
          </td>
        </tr>
      </tbody>
    </table>

    <div
      style="
        display: flex;
        justify-content: space-between;
        font-size: 12px;
        margin-top: 12px;
        padding: 0 2px;
      "
    >
      <span>负责人：</span>
      <span>财务主管：</span>
      <span>出纳：</span>
      <span>制单：{{ record.recorded_by_name || '' }}</span>
    </div>

    <div
      v-if="record.status === 'VOID'"
      style="font-size: 11px; color: #a33; margin-top: 6px"
    >
      注：本单据已作废。
    </div>
  </div>
</template>
