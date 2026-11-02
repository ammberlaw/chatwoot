<script setup>
import { computed } from 'vue';

// 委外发料单 / 委外退料单 / 委外产品入库单 三合一票面（A4 纵向）。
//
// 三张单在库里是同一张表（mes_stock_entries 一表多用），票面结构也一样：
// 抬头＋一张明细表＋签字栏，差别只在标题、仓库那两栏的称谓、和要不要印「应收数量」。
// 所以不拆成三个组件——拆了只会有三份几乎一样的版式各自漂移。
const props = defineProps({
  entry: { type: Object, required: true },
  order: { type: Object, required: true },
  // [{ materialNo, name, unit, qty, plannedQty }]
  items: { type: Array, default: () => [] },
  warehouseName: { type: Function, default: () => '' },
});

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const day = d => (d ? String(d).slice(0, 10) : '');

const META = {
  OUTSOURCE_ISSUE: {
    title: '委外发料单',
    fromLabel: '发出仓库',
    toLabel: '送达仓库',
    qtyLabel: '实发数量',
    showPlanned: true,
    plannedLabel: '应发数量',
  },
  OUTSOURCE_RETURN: {
    title: '委外退料单',
    fromLabel: '退出仓库',
    toLabel: '退回仓库',
    qtyLabel: '退料数量',
    showPlanned: false,
  },
  OUTSOURCE_RECEIPT: {
    title: '委外产品入库单',
    fromLabel: '委外仓库',
    toLabel: '入库仓库',
    qtyLabel: '实收数量',
    showPlanned: true,
    plannedLabel: '应收数量',
  },
};
const meta = computed(() => META[props.entry.purpose] || META.OUTSOURCE_ISSUE);
const totalQty = computed(() =>
  props.items.reduce((acc, row) => acc + Number(row.qty || 0), 0)
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
      {{ meta.title }}
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
        <span>加工厂：{{ order.supplierName || '' }}</span>
        <span>
          {{ meta.fromLabel }}：{{ warehouseName(entry.fromWarehouseId) }}
        </span>
        <span>
          {{ meta.toLabel }}：{{ warehouseName(entry.toWarehouseId) }}
        </span>
      </div>
      <div style="display: flex; flex-direction: column; gap: 6px">
        <span>单据编号：{{ entry.entryNo }}</span>
        <span>委外加工单：{{ order.orderNo }}</span>
        <span>日期：{{ day(entry.postedAt || entry.createdAt) }}</span>
      </div>
    </div>

    <table style="width: 100%; border-collapse: collapse; font-size: 12px">
      <thead>
        <tr>
          <th :style="`${TH}width:38px`">序号</th>
          <th :style="TH">编码</th>
          <th :style="TH">名称</th>
          <th :style="`${TH}width:42px`">单位</th>
          <th v-if="meta.showPlanned" :style="`${TH}width:70px`">
            {{ meta.plannedLabel }}
          </th>
          <th :style="`${TH}width:70px`">{{ meta.qtyLabel }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in items" :key="i">
          <td :style="TD">{{ i + 1 }}</td>
          <td :style="TD">{{ row.materialNo || '' }}</td>
          <td :style="TD">{{ row.name || '' }}</td>
          <td :style="TD">{{ row.unit || '' }}</td>
          <td v-if="meta.showPlanned" :style="TD">{{ num(row.plannedQty) }}</td>
          <td :style="TD">{{ num(row.qty) }}</td>
        </tr>
        <tr>
          <td :style="TD">合计</td>
          <td :style="TD" />
          <td :style="TD" />
          <td :style="TD" />
          <td v-if="meta.showPlanned" :style="TD" />
          <td :style="TD">{{ num(totalQty) }}</td>
        </tr>
      </tbody>
    </table>

    <div style="margin-top: 10px">备注：{{ entry.remark || '' }}</div>
    <div style="display: flex; gap: 70px; margin-top: 16px">
      <span>制单人：{{ order.ownerName || '' }}</span>
      <span>仓管签字：</span>
      <span>加工厂签收：</span>
    </div>
  </div>
</template>
