<script setup>
import { computed } from 'vue';
import { fmtMoney, rmbCapital } from 'dashboard/helper/erpMoney';

// 记账凭证打印版式（中式/金蝶习惯）：
// 标题「记 账 凭 证」+ 凭证字号 / 日期 / 附单据张数；表体逐行摘要+科目+借贷金额；
// 合计行带人民币大写；页脚五个签字栏（制单/审核/记账/出纳/会计主管）。
// 行数不足按会计习惯补空行，票面高度稳定，撕联对齐。
const props = defineProps({
  voucher: { type: Object, required: true },
  minRows: { type: Number, default: 5 },
});

const lines = computed(() => props.voucher.lines || []);
const filler = computed(() => Math.max(0, props.minRows - lines.value.length));
const isDebit = line => line.direction === 'DEBIT';
// 打印金额一律本位币（外币按录入汇率折算后的记账金额）。
const amount = line => fmtMoney(line.base_amount_micros);

const totalDebit = computed(() => props.voucher.total_debit_micros || 0);
const capital = computed(() => rmbCapital(totalDebit.value));

const dimensionText = line =>
  [
    line.crm_customer_name,
    line.mes_supplier_name,
    line.crm_sales_order_no,
    line.department_name,
    line.member_name,
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- 打印票面**必须**用内联样式：printHelper 克隆节点后只把白名单里的计算样式内联进去，
     列宽（width）不在白名单内，靠 Tailwind class 的宽度在打印媒体下会丢，票面列会塌。
     内联 style 随 cloneNode 一起带走，是这里唯一稳的写法。 -->
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
      记 账 凭 证
    </div>

    <div
      style="
        display: flex;
        justify-content: space-between;
        font-size: 12px;
        margin: 10px 2px 6px;
      "
    >
      <span>日期：{{ voucher.voucher_date }}</span>
      <span>凭证字号：{{ voucher.voucher_no }}</span>
      <span>附单据：{{ voucher.attachment_count || 0 }} 张</span>
    </div>

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
          <th style="border: 1px solid #333; padding: 5px; width: 26%">
            摘 要
          </th>
          <th style="border: 1px solid #333; padding: 5px">会 计 科 目</th>
          <th style="border: 1px solid #333; padding: 5px; width: 18%">
            借方金额
          </th>
          <th style="border: 1px solid #333; padding: 5px; width: 18%">
            贷方金额
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="line in lines" :key="line.id">
          <td style="border: 1px solid #333; padding: 5px; height: 26px">
            {{ line.summary || voucher.summary || '' }}
          </td>
          <td style="border: 1px solid #333; padding: 5px">
            {{ line.ledger_account_code }} {{ line.ledger_account_name }}
            <span v-if="dimensionText(line)" style="color: #555">
              （{{ dimensionText(line) }}）
            </span>
          </td>
          <td
            style="
              border: 1px solid #333;
              padding: 5px;
              text-align: right;
              font-variant-numeric: tabular-nums;
            "
          >
            {{ isDebit(line) ? amount(line) : '' }}
          </td>
          <td
            style="
              border: 1px solid #333;
              padding: 5px;
              text-align: right;
              font-variant-numeric: tabular-nums;
            "
          >
            {{ isDebit(line) ? '' : amount(line) }}
          </td>
        </tr>
        <tr v-for="n in filler" :key="`filler-${n}`">
          <td style="border: 1px solid #333; padding: 5px; height: 26px">
            &nbsp;
          </td>
          <td style="border: 1px solid #333; padding: 5px" />
          <td style="border: 1px solid #333; padding: 5px" />
          <td style="border: 1px solid #333; padding: 5px" />
        </tr>
        <tr>
          <td colspan="2" style="border: 1px solid #333; padding: 5px">
            合计（人民币大写）：{{ capital }}
          </td>
          <td
            style="
              border: 1px solid #333;
              padding: 5px;
              text-align: right;
              font-weight: 700;
              font-variant-numeric: tabular-nums;
            "
          >
            {{ fmtMoney(voucher.total_debit_micros) }}
          </td>
          <td
            style="
              border: 1px solid #333;
              padding: 5px;
              text-align: right;
              font-weight: 700;
              font-variant-numeric: tabular-nums;
            "
          >
            {{ fmtMoney(voucher.total_credit_micros) }}
          </td>
        </tr>
      </tbody>
    </table>

    <div
      style="
        display: flex;
        justify-content: space-between;
        font-size: 12px;
        margin-top: 10px;
        padding: 0 2px;
      "
    >
      <!-- 审核/出纳/会计主管是纸面手签栏，系统里没有对应角色就留空，别拿记账人顶替。 -->
      <span>会计主管：</span>
      <span>审核：</span>
      <span>出纳：</span>
      <span>记账：{{ voucher.posted_by_name || '' }}</span>
      <span>制单：{{ voucher.prepared_by_name || '' }}</span>
    </div>

    <div
      v-if="voucher.status !== 'POSTED'"
      style="font-size: 11px; color: #a33; margin-top: 6px"
    >
      注：本张凭证当前为「{{ voucher.status_label }}」，未记账。
    </div>
  </div>
</template>
