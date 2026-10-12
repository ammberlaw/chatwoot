<script setup>
import { computed } from 'vue';
import MesTriplicateSheet from './MesTriplicateSheet.vue';

// 采购入库单票面：1:1 对标公司在用的旧系统那张（三联复写纸、针式打印机套打）。
// 抬头一行「供应商 / 日期 / 编号」，明细列固定九列，末行合计只对应收/实收两列，
// 最下面五个签字位。单价金额不进这张票——它是仓库跟供应商对数量的凭据。
const props = defineProps({
  entry: { type: Object, required: true },
  // [{ sourceNo, materialNo, name, spec, warehouse, unit, qty, receivedQty, remark }]
  items: { type: Array, default: () => [] },
  supplier: { type: String, default: '' },
});

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const day = d => (d ? String(d).slice(0, 10) : '');
const sum = key =>
  props.items.reduce((acc, row) => acc + Number(row[key] || 0), 0);
const totalQty = computed(() => sum('qty'));
const totalReceived = computed(() => sum('receivedQty'));

const TH = 'padding:3px 4px;border:1px solid #000;font-weight:400;';
const TD = 'padding:3px 4px;border:1px solid #000;';
// 窄列必须不折行：中文可以在任意字之间断开，列一窄「收料仓库」就被压成逐字竖排，
// 「源单单号」也会断成两行——旧系统那张不是这样的。
const NOWRAP = 'white-space:nowrap;';
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<template>
  <MesTriplicateSheet title="采购入库单">
    <template #header>
      <div
        style="
          display: flex;
          justify-content: space-between;
          gap: 16px;
          margin-bottom: 4px;
        "
      >
        <span>供应商：{{ supplier || '' }}</span>
        <span>日期：{{ day(entry.postedAt || entry.actualInboundDate) }}</span>
        <span>编号：{{ entry.entryNo }}</span>
      </div>
    </template>

    <table
      style="
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        table-layout: fixed;
      "
    >
      <colgroup>
        <col style="width: 108px" />
        <col style="width: 92px" />
        <col style="width: 96px" />
        <col />
        <col style="width: 66px" />
        <col style="width: 34px" />
        <col style="width: 46px" />
        <col style="width: 46px" />
        <col style="width: 104px" />
      </colgroup>
      <thead>
        <tr>
          <th :style="`${TH}${NOWRAP}`">源单单号</th>
          <th :style="`${TH}${NOWRAP}`">物料编码</th>
          <th :style="`${TH}${NOWRAP}`">物料名称</th>
          <th :style="`${TH}${NOWRAP}`">规格型号</th>
          <th :style="`${TH}${NOWRAP}`">收料仓库</th>
          <th :style="`${TH}${NOWRAP}`">单位</th>
          <th :style="TH">应收<br />数量</th>
          <th :style="TH">实收<br />数量</th>
          <th :style="`${TH}${NOWRAP}`">备注</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in items" :key="i">
          <td :style="`${TD}${NOWRAP}`">{{ row.sourceNo || '' }}</td>
          <td :style="`${TD}${NOWRAP}`">{{ row.materialNo || '' }}</td>
          <td :style="TD">{{ row.name || '' }}</td>
          <td :style="TD">{{ row.spec || '' }}</td>
          <td :style="`${TD}${NOWRAP}`">{{ row.warehouse || '' }}</td>
          <td :style="`${TD}${NOWRAP}`">{{ row.unit || '' }}</td>
          <td :style="`${TD}text-align:right`">{{ num(row.qty) }}</td>
          <td :style="`${TD}text-align:right`">{{ num(row.receivedQty) }}</td>
          <td :style="TD">{{ row.remark || '' }}</td>
        </tr>
        <!-- 合计只落在应收/实收两列下面，跟旧系统那张一致 -->
        <tr>
          <td :style="`${TD}text-align:center`" colspan="6">合计</td>
          <td :style="`${TD}text-align:right`">{{ num(totalQty) }}</td>
          <td :style="`${TD}text-align:right`">{{ num(totalReceived) }}</td>
          <td :style="TD" />
        </tr>
      </tbody>
    </table>

    <div
      style="
        display: flex;
        justify-content: space-between;
        gap: 8px;
        margin-top: 10px;
      "
    >
      <span>审核：</span>
      <span>记账：</span>
      <span>验收：</span>
      <span>保管：</span>
      <span>制单：{{ entry.ownerName || '' }}</span>
    </div>
  </MesTriplicateSheet>
</template>
