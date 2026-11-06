<script setup>
// 报价单在线预览：只读地看一张已存的报价单。
// 排版本体在 CrmQuoteDocument——新建/编辑弹窗右侧的实时预览渲染的是同一个组件，
// 所以人在编辑时看到的就是这里、也是导出的 Excel 的样子。这个文件只管取数和导出。
import { ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import QuotesAPI from 'dashboard/api/crm/quotes';
import CrmQuoteDocument from './CrmQuoteDocument.vue';

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
      <CrmQuoteDocument :doc="doc" />
    </div>
  </Dialog>
</template>
