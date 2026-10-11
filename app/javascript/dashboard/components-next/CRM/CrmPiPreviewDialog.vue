<script setup>
// PI 在线预览：按导出的 Excel 模板 1:1 排版（抬头 / 买方与运输 / 明细 / 合计 / 条款 / 银行 / 页脚），
// 只读、不改数据。公司抬头与银行块由后端 preview 接口给（与导出同一份常量），前端不另抄。
import { ref, computed } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PisAPI from 'dashboard/api/crm/pis';
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
    const { data } = await PisAPI.preview(accountId.value, id);
    doc.value = camelcaseKeys(data, { deep: true });
  } catch {
    useAlert('预览加载失败');
  } finally {
    loading.value = false;
  }
};
defineExpose({ open });

const items = computed(() => doc.value?.items || []);
const cur = computed(() => doc.value?.currency || 'USD');

// 金额一律两位小数 + 千分位，和导出的 Excel 对得上（micros：1 元 = 1_000_000）。
const money = micros =>
  micros == null
    ? ''
    : `${cur.value} ${(Number(micros) / 1_000_000).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;
const qtyText = q => (q == null ? '' : Number(q).toLocaleString('en-US'));
// 接口回的是 ISO 时间串，单据上只要日期。
const dateText = v => (v ? String(v).slice(0, 10) : '—');

const lineAmount = item => {
  if (item.amountMicros != null) return item.amountMicros;
  if (item.quantity == null || item.unitPriceMicros == null) return null;
  return item.quantity * item.unitPriceMicros;
};

// 合计由后端按导出同一算法算好（各项金额 + 运费），前端不另算，保证和导出的 Excel 一致。
const grandTotal = computed(() => doc.value?.grandTotalMicros ?? 0);

const download = async () => {
  if (!doc.value) return;
  downloading.value = true;
  try {
    const { data: blob } = await PisAPI.xlsx(accountId.value, doc.value.id);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PI-${doc.value.piNo || 'export'}.xlsx`;
    a.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert('导出失败');
  } finally {
    downloading.value = false;
  }
};

// 导出 PDF：直接把屏幕上这张单子截成 A4。jspdf / html2canvas 按需加载，不进主包。
// 预览本身是自适应宽度的，所以先克隆到离屏、钉死 A4 宽（794px ＝ 210mm @96dpi）再截，
// 否则窗口宽窄不同导出的比例会跟着变。超过一页按页高切片续页。
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
    pdf.save(`PI-${doc.value.piNo || 'export'}.pdf`);
  } catch (error) {
    // 别把原因吞掉：html2canvas 碰到不认识的 CSS 颜色函数、跨域图片都会抛，
    // 只弹一句「导出失败」等于让人去猜。
    // eslint-disable-next-line no-console
    console.error('[PI PDF]', error);
    useAlert(`PDF 导出失败：${error?.message || error}`);
  } finally {
    if (holder) document.body.removeChild(holder);
    pdfing.value = false;
  }
};

const BUYER_FIELDS = [
  ['Attention', 'attention'],
  ['Company', 'buyerCompany'],
  ['Address', 'buyerAddress'],
  ['Email', 'buyerEmail'],
  ['Tel.', 'buyerTel'],
  ['EORI', 'buyerEori'],
];
const SHIP_FIELDS = [
  ['Port of Shipment', 'portOfShipment'],
  ['Port of Destination', 'portOfDestination'],
  ['Country of Origin', 'countryOfOrigin'],
  ['Currency', 'currency'],
  ['Shipping Method', 'shippingMethod'],
];
// SWIFT 在模板里和 Bank 同一行（右半边），所以不单列一行，见模板 row 32。
const BANK_FIELDS = [
  ['Beneficiary', 'beneficiary'],
  ['Account No.', 'accountLine'],
  ['Bank', 'bank'],
  ['Bank Address', 'bankAddress'],
];
const val = (obj, key) => (obj?.[key] ? String(obj[key]) : '—');
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="5xl"
    title="PI 预览"
    overflow-y-auto
    :show-confirm-button="false"
    cancel-button-label="关闭"
  >
    <template #title>
      <span class="flex items-center gap-2">
        PI 预览
        <span v-if="doc" class="font-mono text-sm text-n-slate-11">
          {{ doc.piNo }}
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

    <!-- 文档本体：严格照 lib/pi/pi_template.xlsx 的版式与配色复刻（段标题灰底白字 #A6A6A6、
         字段标签浅底 #F3F6F9、表头 #E8EEF3、框线 #CDD6DF），所以预览 / PDF / 导出的 Excel 三者长一样。 -->
    <div
      v-else-if="doc"
      ref="docRef"
      class="p-6 overflow-x-auto bg-white border rounded-lg sm:p-8 border-n-weak"
    >
      <div class="min-w-[680px] text-[13px] leading-[1.45] text-[#243746]">
        <!-- 信头：左 logo，右 公司名 / 联系 / 邮箱 / 地址 -->
        <div class="flex items-start justify-between gap-6 pb-3">
          <img :src="letterhead" alt="Wintouch" class="h-11 shrink-0" />
          <div class="text-right">
            <div class="text-[20px] font-bold leading-tight text-[#13293D]">
              {{ doc.company.name }}
            </div>
            <div class="text-[12px] text-[#64748B] whitespace-pre-line">
              {{ doc.seller.contactLine }}
            </div>
            <div class="text-[12px] text-[#64748B] whitespace-pre-line">
              {{ doc.seller.emailLine }}
            </div>
            <div class="text-[12px] text-[#64748B] max-w-[430px] ms-auto">
              {{ doc.company.address }}
            </div>
          </div>
        </div>

        <div
          class="py-1 text-[26px] font-bold text-center text-white bg-[#A6A6A6]"
        >
          PROFORMA INVOICE
        </div>

        <!-- INVOICE NO. / DATE：四等分 -->
        <div class="flex border-b border-x border-[#CDD6DF]">
          <div
            class="w-1/4 px-2 py-1.5 text-[12px] font-bold text-center text-[#13293D] bg-[#E8EEF3] border-e border-[#CDD6DF]"
          >
            INVOICE NO.
          </div>
          <div
            class="w-1/4 px-2 py-1.5 text-[17px] font-bold text-center border-e border-[#CDD6DF]"
          >
            {{ doc.piNo || '—' }}
          </div>
          <div
            class="w-1/4 px-2 py-1.5 text-[12px] font-bold text-center text-[#13293D] bg-[#E8EEF3] border-e border-[#CDD6DF]"
          >
            DATE
          </div>
          <div class="w-1/4 px-2 py-1.5 text-[17px] font-bold text-center">
            {{ dateText(doc.piDate) }}
          </div>
        </div>

        <!-- BILL TO / SHIPMENT & PAYMENT -->
        <div class="flex mt-3">
          <div class="w-1/2 px-2 py-1 font-bold text-white bg-[#A6A6A6]">
            BILL TO
          </div>
          <div
            class="w-1/2 px-2 py-1 font-bold text-white border-s border-white bg-[#A6A6A6]"
          >
            SHIPMENT &amp; PAYMENT
          </div>
        </div>
        <div class="flex">
          <div class="w-1/2">
            <div
              v-for="f in BUYER_FIELDS"
              :key="f[0]"
              class="flex border-b border-x border-[#CDD6DF]"
            >
              <div
                class="w-[25%] shrink-0 px-2 py-1 text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
              >
                {{ f[0] }}
              </div>
              <div class="px-2 py-1 break-words whitespace-pre-line">
                {{ val(doc, f[1]) }}
              </div>
            </div>
          </div>
          <div class="w-1/2">
            <div
              v-for="f in SHIP_FIELDS"
              :key="f[0]"
              class="flex border-b border-e border-[#CDD6DF]"
            >
              <div
                class="w-[29%] shrink-0 px-2 py-1 text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
              >
                {{ f[0] }}
              </div>
              <div class="px-2 py-1 break-words">{{ val(doc, f[1]) }}</div>
            </div>
          </div>
        </div>

        <!-- PRODUCT DETAILS -->
        <div class="px-2 py-1 mt-3 font-bold text-white bg-[#A6A6A6]">
          PRODUCT DETAILS
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
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                MODEL
              </th>
              <th
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                PICTURE
              </th>
              <th
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                DESCRIPTION
              </th>
              <th
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                QTY
              </th>
              <th
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                UNIT PRICE
              </th>
              <th
                class="px-2 py-1 border border-[#CDD6DF] bg-[#E8EEF3] whitespace-nowrap"
              >
                AMOUNT
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="it in items" :key="it.id" class="align-middle">
              <td class="px-2 py-2 break-words border border-[#CDD6DF]">
                {{ it.model }}
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
                {{ it.description }}
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
                {{ money(lineAmount(it)) }}
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
              v-if="doc.shippingCostMicros != null"
              class="font-bold bg-[#F3F6F9]"
            >
              <td
                colspan="5"
                class="px-2 py-1.5 text-right border border-[#CDD6DF] text-[#13293D]"
              >
                {{ doc.shippingCostLabel || 'SHIPPING COST' }}
              </td>
              <td
                class="px-1.5 py-1.5 text-[12px] text-center whitespace-nowrap border border-[#CDD6DF] tabular-nums"
              >
                {{ money(doc.shippingCostMicros) }}
              </td>
            </tr>
            <tr class="font-bold bg-[#F3F6F9]">
              <td
                colspan="5"
                class="px-2 py-1.5 text-right border border-[#CDD6DF] text-[#13293D]"
              >
                GRAND TOTAL
              </td>
              <td
                class="px-1.5 py-1.5 text-[12px] text-center whitespace-nowrap border border-[#CDD6DF] tabular-nums"
              >
                {{ money(grandTotal) }}
              </td>
            </tr>
          </tbody>
        </table>

        <!-- TERMS & CONDITIONS：条款文本自带「1. / 2.」编号，这里不再另加 -->
        <div
          v-if="doc.termLines?.length"
          class="px-2 py-1 mt-3 font-bold text-white bg-[#A6A6A6]"
        >
          TERMS &amp; CONDITIONS
        </div>
        <div
          v-for="(line, i) in doc.termLines || []"
          :key="i"
          class="px-2 py-1 border-b border-x border-[#CDD6DF] whitespace-pre-line"
        >
          {{ line }}
        </div>

        <!-- BANK DETAILS -->
        <div class="px-2 py-1 mt-3 font-bold text-white bg-[#A6A6A6]">
          BANK DETAILS
        </div>
        <div
          v-for="f in BANK_FIELDS"
          :key="f[0]"
          class="flex border-b border-x border-[#CDD6DF]"
        >
          <div
            class="w-[23.6%] shrink-0 px-2 py-1 text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
          >
            {{ f[0] }}
          </div>
          <div class="px-2 py-1 break-words">{{ val(doc.company, f[1]) }}</div>
          <template v-if="f[0] === 'Bank'">
            <div
              class="w-[16%] shrink-0 px-2 py-1 ms-auto text-[12px] font-bold text-[#13293D] bg-[#F3F6F9]"
            >
              SWIFT
            </div>
            <div class="px-2 py-1 w-[18%] shrink-0">
              {{ doc.company.swift }}
            </div>
          </template>
        </div>

        <div class="pt-5 font-bold text-right whitespace-pre-line">
          ISSUED BY{{ '\n' }}{{ doc.issuedBy || '—' }}
        </div>

        <div
          class="px-2 py-1 mt-4 text-[12px] font-bold text-center text-white bg-[#A6A6A6]"
        >
          {{ doc.company.footer }}
        </div>
      </div>
    </div>
  </Dialog>
</template>
