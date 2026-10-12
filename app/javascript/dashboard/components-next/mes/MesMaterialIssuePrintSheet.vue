<script setup>
import { computed } from 'vue';

// 生产领料单票面：1:1 对标公司在用的旧系统那张（A4 纵向，激光打印，不是三联纸）。
// 抬头左边「仓管员 / 领料人」两个签字位留空给现场手写，右边「单据日期 / 单据编号」；
// 明细八列，末行合计只落在数量列；最下面制单人 / 审核人，再下面整单备注。
const props = defineProps({
  entry: { type: Object, required: true },
  // [{ materialNo, name, spec, qty, unit, warehouse, remark }]
  items: { type: Array, default: () => [] },
});

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const day = d => (d ? String(d).slice(0, 10) : '');
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
      生产领料单
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
        <!-- 两个签字位留空：现场手写，系统里没有这两个角色的落款 -->
        <span>仓管员：</span>
        <span>领料人：</span>
      </div>
      <div style="display: flex; flex-direction: column; gap: 6px">
        <span>单据日期：{{ day(entry.postedAt || entry.createdAt) }}</span>
        <span>单据编号：{{ entry.entryNo }}</span>
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
          <th :style="`${TH}width:46px`">单位</th>
          <th :style="`${TH}width:64px`">仓库</th>
          <th :style="TH">物料行备注</th>
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
          <td :style="TD">{{ row.warehouse || '' }}</td>
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
          <td :style="TD" />
        </tr>
      </tbody>
    </table>

    <div style="display: flex; gap: 90px; margin-top: 12px">
      <span>制单人：{{ entry.ownerName || '' }}</span>
      <span>审核人：{{ entry.checkedByName || '' }}</span>
    </div>
    <div style="margin-top: 10px">备注：{{ entry.remark || '' }}</div>
  </div>
</template>
