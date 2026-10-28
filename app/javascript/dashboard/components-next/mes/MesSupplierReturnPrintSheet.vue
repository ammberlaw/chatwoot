<script setup>
import { computed } from 'vue';

// 采购退料单票面：照生产领料单那张的版式（A4 纵向，激光打印）。
//
// 比领料单多三样，都是用户 2026-10-29 点名要的：**价格/金额**（供应商要凭这个退钱或换货）、
// **关联单号**（采购单 + 收这批货的入库单，供应商和财务都按这个对）、
// **怎么退**（换新的 / 不要了——供应商看了才知道要不要寄新的回来）。
// 「库存」只在屏幕上给仓管参考，不印：供应商拿到这张单不需要知道我们仓里还剩多少。
const props = defineProps({
  record: { type: Object, required: true },
  // [{ materialNo, name, spec, qty, unit, price, amount, remark }]
  items: { type: Array, default: () => [] },
});

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const money = v =>
  v === null || v === undefined || v === '' || Number(v) === 0
    ? ''
    : Number(v).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
const day = d => (d ? String(d).slice(0, 10) : '');
const totalQty = computed(() =>
  props.items.reduce((acc, row) => acc + Number(row.qty || 0), 0)
);
const totalAmount = computed(() =>
  props.items.reduce((acc, row) => acc + Number(row.amount || 0), 0)
);
const kindText = computed(() =>
  props.record.returnKind === 'REFUND'
    ? '退货（不再补发）'
    : '退换（请补发新品）'
);

const TH =
  'padding:4px 5px;border:1px solid #000;font-weight:400;text-align:left;';
const TD = 'padding:4px 5px;border:1px solid #000;vertical-align:top;';
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<!-- 票面必须内联样式：printElement 只把白名单计算样式内联进克隆，靠 class 的边框会丢。 -->
<template>
  <div
    class="mes-print-sheet"
    style="
      width: 700px;
      color: #000;
      font-family: 'Songti SC', 'SimSun', serif;
      font-size: 12px;
    "
  >
    <div
      style="
        text-align: center;
        font-size: 18px;
        font-weight: 700;
        letter-spacing: 4px;
        margin-bottom: 14px;
      "
    >
      采购退料单
    </div>

    <div
      style="
        display: flex;
        justify-content: space-between;
        gap: 24px;
        margin-bottom: 8px;
      "
    >
      <div style="display: flex; flex-direction: column; gap: 6px">
        <span>供应商：{{ record.supplierName || '' }}</span>
        <span>退料方式：{{ kindText }}</span>
        <span>退料仓库：{{ record.warehouseName || '' }}</span>
      </div>
      <div style="display: flex; flex-direction: column; gap: 6px">
        <span>单据编号：{{ record.returnNo }}</span>
        <span>退出日期：{{ day(record.sentOn) }}</span>
        <span>
          关联单号：{{ record.purchaseOrderNo || '—' }}
          <template v-if="record.sourceEntryNo">
            / {{ record.sourceEntryNo }}
          </template>
        </span>
      </div>
    </div>

    <table style="width: 100%; border-collapse: collapse; font-size: 12px">
      <thead>
        <tr>
          <th :style="`${TH}width:38px`">序号</th>
          <th :style="TH">物料编码</th>
          <th :style="TH">物料名称</th>
          <th :style="TH">规格型号</th>
          <th :style="`${TH}width:56px`">数量</th>
          <th :style="`${TH}width:42px`">单位</th>
          <th :style="`${TH}width:62px`">单价</th>
          <th :style="`${TH}width:70px`">金额</th>
          <th :style="TH">备注</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in items" :key="i">
          <td :style="TD">{{ i + 1 }}</td>
          <td :style="TD">{{ row.materialNo || '' }}</td>
          <td :style="TD">{{ row.name || '' }}</td>
          <td :style="TD">{{ row.spec || '' }}</td>
          <td :style="TD">{{ num(row.qty) }}</td>
          <td :style="TD">{{ row.unit || '' }}</td>
          <td :style="TD">{{ money(row.price) }}</td>
          <td :style="TD">{{ money(row.amount) }}</td>
          <td :style="TD">{{ row.remark || '' }}</td>
        </tr>
        <tr>
          <td :style="TD">合计</td>
          <td :style="TD" />
          <td :style="TD" />
          <td :style="TD" />
          <td :style="TD">{{ num(totalQty) }}</td>
          <td :style="TD" />
          <td :style="TD" />
          <td :style="TD">{{ money(totalAmount) }}</td>
          <td :style="TD" />
        </tr>
      </tbody>
    </table>

    <div style="margin-top: 10px">退料原因：{{ record.reason || '' }}</div>
    <div style="margin-top: 6px">备注：{{ record.remark || '' }}</div>
    <div style="display: flex; gap: 70px; margin-top: 16px">
      <span>制单人：{{ record.ownerName || '' }}</span>
      <span>仓管签收：</span>
      <span>供应商签收：</span>
    </div>
  </div>
</template>
