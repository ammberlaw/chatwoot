<script setup>
// 报价单在线预览：按导出的 Excel 模板（lib/quote/quote_template.xlsx 的 Quotation 表）1:1 排版，
// 只读。抬头、右栏默认条款、条款正文、页脚都由后端 preview 接口从模板里读出来给，前端不另抄文案。
// 与 PI 预览同一套版式与配色（段标题 #A6A6A6 白字 / 标签 #F3F6F9 / 表头 #E8EEF3 / 框线 #CDD6DF）。
import { ref, computed } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import QuotesAPI from 'dashboard/api/crm/quotes';
import letterhead from 'dashboard/assets/images/wintouch/pi-letterhead.png';

const emit = defineEmits(['edit']);

const { accountId } = useAccount();
const dialogRef = ref(null);
const docRef = ref(null);
const doc = ref(null);
const loading = ref(false);
const downloading = ref(false);
const pdfing = ref(false);

const open = async id => {
  doc.value = null;
  loading.value = true;
  dialogRef.value?.open();
  try {
    const { data } = await QuotesAPI.preview(accountId.value, id);
    doc.value = camelcaseKeys(data, { deep: true });
  } catch {
    useAlert('预览加载失败');
  } finally {
    loading.value = false;
  }
};
defineExpose({ open });

const tpl = computed(() => doc.value?.template || {});
const items = computed(() => doc.value?.lineItems || []);
const cur = computed(() => doc.value?.quoteCurrency || 'USD');

const money = micros =>
  micros == null
    ? ''
    : `${cur.value} ${(Number(micros) / 1_000_000).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;
const qtyText = q => (q == null ? '' : Number(q).toLocaleString('en-US'));
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
    value: doc.value?.buyer?.[BUYER_KEYS[i]] || '—',
  }))
);
// 右栏（报价条款）：第一格币种随单据走，其余是模板固定值。
const termRows = computed(() =>
  (tpl.value.rightLabels || []).map((label, i) => ({
    label,
    value: (i === 0 ? cur.value : tpl.value.rightDefaults?.[i]) || '—',
  }))
);

const download = async () => {
  if (!doc.value) return;
  downloading.value = true;
  try {
    const { data: blob } = await QuotesAPI.xlsx(accountId.value, doc.value.id);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `Quote-${doc.value.quoteNo || 'export'}.xlsx`;
    a.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert('导出失败');
  } finally {
    downloading.value = false;
  }
};

// 导出 PDF：与 PI 预览同一套做法——克隆到离屏钉死 A4 宽再截图，超一页按页高切片。
const A4_WIDTH_PX = 794;
const exportPdf = async () => {
  if (!doc.value || pdfing.value) return;
  pdfing.value = true;
  let holder = null;
  try {
    const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
      import('html2canvas'),
      import('jspdf'),
    ]);
    const PdfDoc = jsPDF;
    holder = document.createElement('div');
    holder.style.cssText = `position:fixed;left:-10000px;top:0;width:${A4_WIDTH_PX}px;background:#fff;`;
    const clone = docRef.value.cloneNode(true);
    clone.style.width = `${A4_WIDTH_PX}px`;
    clone.style.maxWidth = 'none';
    clone.style.overflow = 'visible';
    holder.appendChild(clone);
    document.body.appendChild(holder);

    const canvas = await html2canvas(clone, {
      scale: 2,
      backgroundColor: '#ffffff',
      useCORS: true,
      logging: false,
    });
    const pdf = new PdfDoc({ unit: 'pt', format: 'a4' });
    const pageW = pdf.internal.pageSize.getWidth();
    const pageH = pdf.internal.pageSize.getHeight();
    const imgH = (canvas.height * pageW) / canvas.width;
    const image = canvas.toDataURL('image/jpeg', 0.95);
    pdf.addImage(image, 'JPEG', 0, 0, pageW, imgH);
    let remaining = imgH - pageH;
    let offset = 0;
    while (remaining > 0) {
      offset -= pageH;
      pdf.addPage();
      pdf.addImage(image, 'JPEG', 0, offset, pageW, imgH);
      remaining -= pageH;
    }
    pdf.save(`Quote-${doc.value.quoteNo || 'export'}.pdf`);
  } catch {
    useAlert('PDF 导出失败');
  } finally {
    if (holder) document.body.removeChild(holder);
    pdfing.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="5xl"
    title="报价单预览"
    overflow-y-auto
    :show-confirm-button="false"
    cancel-button-label="关闭"
  >
    <template #title>
      <span class="flex items-center gap-2">
        报价单预览
        <span v-if="doc" class="font-mono text-sm text-n-slate-11">
          {{ doc.quoteNo }}
        </span>
      </span>
    </template>
    <template #headerActions>
      <div class="flex items-center gap-2">
        <Button
          sm
          variant="faded"
          color="slate"
          label="编辑"
          icon="i-lucide-pencil"
          @click="emit('edit', doc)"
        />
        <Button
          sm
          variant="faded"
          color="slate"
          :label="pdfing ? '生成中…' : '导出 PDF'"
          icon="i-lucide-file-text"
          :disabled="pdfing || !doc"
          @click="exportPdf"
        />
        <Button
          sm
          color="iris"
          :label="downloading ? '导出中…' : '导出 Excel'"
          icon="i-lucide-download"
          :disabled="downloading || !doc"
          @click="download"
        />
      </div>
    </template>

    <div v-if="loading" class="py-16 text-sm text-center text-n-slate-11">
      加载中…
    </div>

    <div
      v-else-if="doc"
      ref="docRef"
      class="p-6 overflow-x-auto bg-white border rounded-lg sm:p-8 border-n-weak"
    >
      <div class="min-w-[680px] text-[13px] leading-[1.45] text-[#243746]">
        <!-- 信头 -->
        <div class="flex items-start justify-between gap-6 pb-3">
          <img :src="letterhead" alt="Wintouch" class="h-11 shrink-0" />
          <div class="text-right">
            <div class="text-[20px] font-bold leading-tight text-[#13293D]">
              {{ tpl.companyName }}
            </div>
            <div class="text-[12px] text-[#64748B] whitespace-pre-line">
              {{ doc.seller.contactLine }}
            </div>
            <div class="text-[12px] text-[#64748B] whitespace-pre-line">
              {{ doc.seller.emailLine }}
            </div>
            <div class="text-[12px] text-[#64748B] max-w-[430px] ms-auto">
              {{ tpl.companyAddress }}
            </div>
          </div>
        </div>

        <div
          class="py-1 text-[26px] font-bold text-center text-white bg-[#A6A6A6]"
        >
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
            <tr v-for="it in items" :key="it.id" class="align-middle">
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
              v-for="row in [
                { label: tpl.subtotalLabel, value: doc.subtotalMicros },
                { label: tpl.freightLabel, value: doc.freightMicros },
                { label: tpl.totalLabel, value: doc.totalAmountMicros },
              ]"
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
    </div>
  </Dialog>
</template>
