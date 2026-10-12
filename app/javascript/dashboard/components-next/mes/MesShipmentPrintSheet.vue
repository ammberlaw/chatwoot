<script setup>
import { computed } from 'vue';
import MesTriplicateSheet from './MesTriplicateSheet.vue';

const props = defineProps({
  shipment: { type: Object, required: true },
  // [{ sku, name, spec, warehouse, unit, qty, unitPrice, amount, remark }]
  items: { type: Array, default: () => [] },
});

// 销售出库单票面：1:1 对标公司在用的旧系统那张（三联复写纸、针式打印机套打）。
// 比入库单多一个公司抬头块（名称/地址/电话传真）和右上角页码，明细多单价/金额两列，
// 表下面是「备注 + 交货地点」两栏，最后五个签字位（审核/记账/发货/制单/签收）。
//
// 公司抬头写死联迪：这张单就是以联迪名义发给客户的，不是可配置项。
const COMPANY = {
  name: '东莞市联迪科技有限公司',
  address: '地址:东莞市大岭山镇石大路大岭山段692号1号楼311室',
  tel: 'Tel:0755-81488252',
  fax: 'Fax:0755-28891676',
};

const num = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('zh-CN', { maximumFractionDigits: 3 });
const money = v =>
  v === null || v === undefined || v === ''
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

const TH = 'padding:3px 4px;border:1px solid #000;font-weight:400;';
const TD = 'padding:3px 4px;border:1px solid #000;';
// 窄列不折行：中文能在任意字之间断开，列一窄「发货仓库」就被压成逐字竖排。
const NOWRAP = 'white-space:nowrap;';
</script>

<!-- eslint-disable vue/no-static-inline-styles -->
<template>
  <MesTriplicateSheet title="销售出库单">
    <template #header>
      <div
        style="
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 16px;
        "
      >
        <div style="line-height: 1.5">
          <div style="font-size: 16px; font-weight: 700">
            {{ COMPANY.name }}
          </div>
          <div>{{ COMPANY.address }}</div>
          <div style="display: flex; gap: 28px">
            <span>{{ COMPANY.tel }}</span>
            <span>{{ COMPANY.fax }}</span>
          </div>
        </div>
        <div style="white-space: nowrap">第1页，共1页</div>
      </div>
      <div
        style="
          display: flex;
          justify-content: space-between;
          gap: 16px;
          margin-bottom: 4px;
        "
      >
        <span>购货单位：{{ shipment.customerName || '' }}</span>
        <span>日期：{{ day(shipment.shippedAt || shipment.createdAt) }}</span>
        <span>编 号：{{ shipment.shipmentNo }}</span>
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
        <col style="width: 96px" />
        <col style="width: 130px" />
        <col />
        <col style="width: 70px" />
        <col style="width: 34px" />
        <col style="width: 48px" />
        <col style="width: 58px" />
        <col style="width: 66px" />
        <col style="width: 84px" />
      </colgroup>
      <thead>
        <tr>
          <th :style="`${TH}${NOWRAP}`">产品代码</th>
          <th :style="`${TH}${NOWRAP}`">产品名称</th>
          <th :style="`${TH}${NOWRAP}`">规格型号</th>
          <th :style="`${TH}${NOWRAP}`">发货仓库</th>
          <th :style="`${TH}${NOWRAP}`">单位</th>
          <th :style="`${TH}${NOWRAP}`">数量</th>
          <th :style="`${TH}${NOWRAP}`">单价</th>
          <th :style="`${TH}${NOWRAP}`">金额</th>
          <th :style="`${TH}${NOWRAP}`">备注</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, i) in items" :key="i">
          <td :style="`${TD}${NOWRAP}`">{{ row.sku || '' }}</td>
          <td :style="TD">{{ row.name || '' }}</td>
          <td :style="TD">{{ row.spec || '' }}</td>
          <td :style="`${TD}${NOWRAP}`">{{ row.warehouse || '' }}</td>
          <td :style="`${TD}${NOWRAP}`">{{ row.unit || '' }}</td>
          <td :style="`${TD}text-align:right`">{{ num(row.qty) }}</td>
          <td :style="`${TD}text-align:right`">{{ money(row.unitPrice) }}</td>
          <td :style="`${TD}text-align:right`">{{ money(row.amount) }}</td>
          <td :style="TD">{{ row.remark || '' }}</td>
        </tr>
        <tr>
          <td :style="`${TD}text-align:center`" colspan="5">合计</td>
          <td :style="`${TD}text-align:right`">{{ num(totalQty) }}</td>
          <td :style="TD" />
          <td :style="`${TD}text-align:right`">
            {{ totalAmount ? money(totalAmount) : '' }}
          </td>
          <td :style="TD" />
        </tr>
      </tbody>
    </table>

    <div style="display: flex; gap: 32px; margin-top: 8px">
      <div style="flex: 1; min-width: 0">
        备注： {{ shipment.remark || shipment.salesOrderRemark || '' }}
      </div>
      <div style="flex: 1; min-width: 0">
        交货地点： {{ shipment.customerAddress || '' }}
      </div>
    </div>

    <div
      style="
        display: flex;
        justify-content: space-between;
        gap: 8px;
        margin-top: 12px;
      "
    >
      <span>审核：{{ shipment.managerName || '' }}</span>
      <span>记账：</span>
      <span>发货：</span>
      <span>制单：{{ shipment.ownerName || '' }}</span>
      <span>签收：</span>
    </div>
  </MesTriplicateSheet>
</template>
