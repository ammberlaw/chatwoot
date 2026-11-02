<script setup>
import { computed } from 'vue';

// 委外加工单票面（A4 纵向，激光打印）。给加工厂的那一份：
// 做什么、做多少、什么时候要、加工费多少，以及我们会发哪些料过去。
//
// 分两块和金蝶一致：上面「产出」是双方结算的依据，下面「用料」是发料的依据。
// 标准用量印出来，加工厂才核得了我们发的量对不对。
const props = defineProps({
  record: { type: Object, required: true },
  // [{ itemCode, itemName, unit, stdQty, lossRate }]
  materials: { type: Array, default: () => [] },
});

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const money = v =>
  v === null || v === undefined || v === ''
    ? ''
    : (Number(v) / 1e6).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });
const day = d => (d ? String(d).slice(0, 10) : '');

// 加工费合计＝数量 × 含税单价。双方认的就是这个数。
const feeTotal = computed(
  () =>
    Number(props.record.qty || 0) * Number(props.record.feeRateTaxedMicros || 0)
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
      委外加工单
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
        <span>加工厂：{{ record.supplierName || '' }}</span>
        <span>委外仓：{{ record.outsourceWarehouseName || '' }}</span>
        <span>生产订单：{{ record.productionOrderNo || '—' }}</span>
      </div>
      <div style="display: flex; flex-direction: column; gap: 6px">
        <span>单据编号：{{ record.orderNo }}</span>
        <span>单据日期：{{ day(record.docDate) }}</span>
        <span>交期：{{ day(record.deliveryDate) || '—' }}</span>
      </div>
    </div>

    <div style="margin: 10px 0 4px">产出</div>
    <table style="width: 100%; border-collapse: collapse; font-size: 12px">
      <thead>
        <tr>
          <th :style="TH">商品编码</th>
          <th :style="TH">商品名称</th>
          <th :style="`${TH}width:56px`">数量</th>
          <th :style="`${TH}width:42px`">单位</th>
          <th :style="`${TH}width:72px`">加工费单价</th>
          <th :style="`${TH}width:50px`">税率</th>
          <th :style="`${TH}width:80px`">加工费合计</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td :style="TD">{{ record.productSku || '' }}</td>
          <td :style="TD">{{ record.productName || '' }}</td>
          <td :style="TD">{{ num(record.qty) }}</td>
          <td :style="TD">{{ record.unit || '' }}</td>
          <td :style="TD">{{ money(record.feeRateTaxedMicros) }}</td>
          <td :style="TD">{{ num(record.taxRate) }}%</td>
          <td :style="TD">{{ money(feeTotal) }}</td>
        </tr>
      </tbody>
    </table>

    <div style="margin: 12px 0 4px">我方提供的材料</div>
    <table style="width: 100%; border-collapse: collapse; font-size: 12px">
      <thead>
        <tr>
          <th :style="`${TH}width:38px`">序号</th>
          <th :style="TH">物料编码</th>
          <th :style="TH">物料名称</th>
          <th :style="`${TH}width:42px`">单位</th>
          <th :style="`${TH}width:70px`">应发数量</th>
          <th :style="`${TH}width:56px`">损耗率</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in materials" :key="i">
          <td :style="TD">{{ i + 1 }}</td>
          <td :style="TD">{{ row.itemCode || '' }}</td>
          <td :style="TD">{{ row.itemName || '' }}</td>
          <td :style="TD">{{ row.unit || '' }}</td>
          <td :style="TD">{{ num(row.stdQty) }}</td>
          <td :style="TD">{{ num(row.lossRate) }}%</td>
        </tr>
      </tbody>
    </table>

    <div style="margin-top: 10px">备注：{{ record.remark || '' }}</div>
    <div style="display: flex; gap: 70px; margin-top: 16px">
      <span>制单人：{{ record.ownerName || '' }}</span>
      <span>我方签字：</span>
      <span>加工厂签字：</span>
    </div>
  </div>
</template>
