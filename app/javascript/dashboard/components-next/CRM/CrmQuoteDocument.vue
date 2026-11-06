<script setup>
// 报价单文档本体：按导出的 Excel 模板（lib/quote/quote_template.xlsx 的 Quotation 表）1:1 排版，纯展示。
// 抬头、右栏默认条款、条款正文、页脚都由后端给（preview / preview_meta 同一份来源），前端不另抄文案。
// 与 PI 文档同一套版式与配色（段标题 #A6A6A6 白字 / 标签 #F3F6F9 / 表头 #E8EEF3 / 框线 #CDD6DF）。
//
// 预览弹窗（看已存的单）和新建/编辑弹窗右侧的实时预览都渲染这一个组件——
// 两边各写一份的话，改了排版只改一边，人在编辑时看到的就不是最终发出去的样子。
import { computed } from 'vue';
import letterhead from 'dashboard/assets/images/wintouch/pi-letterhead.png';

const props = defineProps({
  // preview 接口的形状（camelCase）：quoteNo / quoteDate / buyer / seller / lineItems / template …
  doc: { type: Object, required: true },
});

const tpl = computed(() => props.doc.template || {});
const items = computed(() => props.doc.lineItems || []);
const cur = computed(() => props.doc.quoteCurrency || 'USD');

const money = micros =>
  micros == null
    ? ''
    : `${cur.value} ${(Number(micros) / 1_000_000).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;
const qtyText = q =>
  q == null || q === '' ? '' : Number(q).toLocaleString('en-US');
const dateText = v => (v ? String(v).slice(0, 10) : '—');

// 左栏（买方）：标签取自模板，值取自报价单，顺序与模板 11–16 行一致。
const BUYER_KEYS = [
  'contactName',
  'company',
  'country',
  'email',
  'tel',
  'website',
];
const buyerRows = computed(() =>
  (tpl.value.leftLabels || []).map((label, i) => ({
    label,
    value: props.doc.buyer?.[BUYER_KEYS[i]] || '—',
  }))
);
// 右栏（报价条款）：第一格币种随单据走，其余是模板固定值。
const termRows = computed(() =>
  (tpl.value.rightLabels || []).map((label, i) => ({
    label,
    value: (i === 0 ? cur.value : tpl.value.rightDefaults?.[i]) || '—',
  }))
);

const totalRows = computed(() => [
  { label: tpl.value.subtotalLabel, value: props.doc.subtotalMicros },
  { label: tpl.value.freightLabel, value: props.doc.freightMicros },
  { label: tpl.value.totalLabel, value: props.doc.totalAmountMicros },
]);
</script>

<template>
  <div class="min-w-[680px] text-[13px] leading-[1.45] text-[#243746]">
    <!-- 信头 -->
    <div class="flex items-start justify-between gap-6 pb-3">
      <img :src="letterhead" alt="Wintouch" class="h-11 shrink-0" />
      <div class="text-right">
        <div class="text-[20px] font-bold leading-tight text-[#13293D]">
          {{ tpl.companyName }}
        </div>
        <div class="text-[12px] text-[#64748B] whitespace-pre-line">
          {{ doc.seller?.contactLine }}
        </div>
        <div class="text-[12px] text-[#64748B] whitespace-pre-line">
          {{ doc.seller?.emailLine }}
        </div>
        <div class="text-[12px] text-[#64748B] max-w-[430px] ms-auto">
          {{ tpl.companyAddress }}
        </div>
      </div>
    </div>

    <div class="py-1 text-[26px] font-bold text-center text-white bg-[#A6A6A6]">
      {{ tpl.title }}
    </div>

    <!-- QUOTATION NO. / DATE -->
    <div class="flex border-b border-x border-[#CDD6DF]">
      <div
        class="w-1/4 px-2 py-1.5 text-[12px] font-bold text-center text-[#13293D] bg-[#E8EEF3] border-e border-[#CDD6DF]"
      >
        {{ tpl.noLabel }}
      </div>
      <div
        class="w-1/4 px-2 py-1.5 text-[17px] font-bold text-center border-e border-[#CDD6DF]"
      >
        {{ doc.quoteNo || '—' }}
      </div>
      <div
        class="w-1/4 px-2 py-1.5 text-[12px] font-bold text-center text-[#13293D] bg-[#E8EEF3] border-e border-[#CDD6DF]"
      >
        {{ tpl.dateLabel }}
      </div>
      <div class="w-1/4 px-2 py-1.5 text-[17px] font-bold text-center">
        {{ dateText(doc.quoteDate) }}
      </div>
    </div>

    <!-- QUOTED TO / QUOTATION TERMS -->
    <div class="flex mt-3">
      <div class="w-1/2 px-2 py-1 font-bold text-white bg-[#A6A6A6]">
        {{ tpl.leftBand }}
      </div>
      <div
        class="w-1/2 px-2 py-1 font-bold text-white border-s border-white bg-[#A6A6A6]"
      >
        {{ tpl.rightBand }}
      </div>
    </div>
    <div class="flex">
      <div class="w-1/2">
        <div
          v-for="row in buyerRows"
          :key="row.label"
          class="flex border-b border-x border-[#CDD6DF]"
        >
          <div
            class="w-[25%] shrink-0 px-2 py-1 text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
          >
            {{ row.label }}
          </div>
          <div class="px-2 py-1 break-words whitespace-pre-line">
            {{ row.value }}
          </div>
        </div>
      </div>
      <div class="w-1/2">
        <div
          v-for="row in termRows"
          :key="row.label"
          class="flex border-b border-e border-[#CDD6DF]"
        >
          <div
            class="w-[29%] shrink-0 px-2 py-1 text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
          >
            {{ row.label }}
          </div>
          <div class="px-2 py-1 break-words">{{ row.value }}</div>
        </div>
      </div>
    </div>

    <!-- PRODUCT DETAILS -->
    <div class="px-2 py-1 mt-3 font-bold text-white bg-[#A6A6A6]">
      {{ tpl.detailBand }}
    </div>
    <table class="w-full border-collapse table-fixed">
      <colgroup>
        <col class="w-[12.6%]" />
        <col class="w-[22%]" />
        <col class="w-[29.9%]" />
        <col class="w-[11%]" />
        <col class="w-[11.8%]" />
        <col class="w-[12.7%]" />
      </colgroup>
      <thead>
        <tr class="text-[12px] font-bold text-[#13293D]">
          <th
            v-for="col in tpl.columns || []"
            :key="col"
            class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3]"
          >
            {{ col }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(it, i) in items" :key="it.id || i" class="align-middle">
          <td class="px-2 py-2 break-words border border-[#CDD6DF]">
            {{ it.productNameSnapshot || it.name }}
          </td>
          <td class="px-2 py-2 text-center border border-[#CDD6DF]">
            <img
              v-if="it.pictureUrl"
              :src="it.pictureUrl"
              alt=""
              class="object-contain h-16 mx-auto"
            />
          </td>
          <td
            class="px-2 py-2 break-words whitespace-pre-line border border-[#CDD6DF]"
          >
            {{ it.specSnapshot || it.remark }}
          </td>
          <td
            class="px-1.5 py-2 text-[12px] text-right whitespace-nowrap border border-[#CDD6DF] tabular-nums"
          >
            {{ qtyText(it.quantity) }}
          </td>
          <td
            class="px-1.5 py-2 text-[12px] text-right whitespace-nowrap border border-[#CDD6DF] tabular-nums"
          >
            {{ money(it.unitPriceMicros) }}
          </td>
          <td
            class="px-1.5 py-2 text-[12px] text-right whitespace-nowrap border border-[#CDD6DF] tabular-nums"
          >
            {{ money(it.amountMicros) }}
          </td>
        </tr>
        <tr v-if="!items.length">
          <td
            colspan="6"
            class="px-2 py-4 text-center border border-[#CDD6DF] text-[#64748B]"
          >
            暂无明细
          </td>
        </tr>
        <tr
          v-for="row in totalRows"
          :key="row.label"
          class="font-bold bg-[#F3F6F9]"
        >
          <td
            colspan="5"
            class="px-2 py-1.5 text-right border border-[#CDD6DF] text-[#13293D]"
          >
            {{ row.label }}
          </td>
          <td
            class="px-1.5 py-1.5 text-[12px] text-center whitespace-nowrap border border-[#CDD6DF] tabular-nums"
          >
            {{ money(row.value) }}
          </td>
        </tr>
      </tbody>
    </table>

    <!-- TERMS & CONDITIONS：条款正文自带编号，不再另加 -->
    <div
      v-if="tpl.terms?.length"
      class="px-2 py-1 mt-3 font-bold text-white bg-[#A6A6A6]"
    >
      {{ tpl.termsBand }}
    </div>
    <div
      v-for="(line, i) in tpl.terms || []"
      :key="i"
      class="px-2 py-1 border-b border-x border-[#CDD6DF] whitespace-pre-line"
    >
      {{ line }}
    </div>

    <div class="pt-5 font-bold text-right whitespace-pre-line">
      ISSUED BY{{ '\n' }}{{ doc.issuedBy || '—' }}
    </div>

    <div
      class="px-2 py-1 mt-4 text-[12px] font-bold text-center text-white bg-[#A6A6A6]"
    >
      {{ tpl.footer }}
    </div>
  </div>
</template>
