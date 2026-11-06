<script setup>
// PI 在线预览：只读地看一张已存的 PI，外加发出前体检与导出。
// 排版本体在 CrmPiDocument——新建/编辑弹窗右侧的实时预览渲染的是同一个组件，
// 所以人在编辑时看到的就是这里、也是导出的 Excel 的样子。
import { ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PisAPI from 'dashboard/api/crm/pis';
import CrmPiDocument from './CrmPiDocument.vue';

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

// 发出前体检：算术对不对、条款缺不缺、币种和这家客户以往一不一致、单价和历史价差多少。
// 放在预览弹窗里是因为这儿就是「发出去之前最后看一眼」的地方——
// 真正能挡住错误的时刻只有这一刻，放列表页或编辑页都隔了一层。
const checking = ref(false);
const findings = ref(null);

const runHealthCheck = async () => {
  if (!doc.value) return;
  checking.value = true;
  try {
    const { data } = await PisAPI.healthCheck(accountId.value, doc.value.id);
    findings.value = data.payload || [];
  } catch (error) {
    findings.value = null;
    useAlert('体检失败，请稍后再试');
  } finally {
    checking.value = false;
  }
};

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
          :label="checking ? '体检中…' : '发出前体检'"
          icon="i-lucide-stethoscope"
          :disabled="checking || !doc"
          @click="runHealthCheck"
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

    <!-- 体检结果。没问题也要明说「没查出问题」——只在有问题时才出现的话，
         用户分不清是查过了没事，还是压根没查。 -->
    <div
      v-if="findings"
      class="p-3 mb-3 text-sm border rounded-lg"
      :class="
        findings.length
          ? 'border-n-amber-8 bg-n-amber-3 text-n-amber-11'
          : 'border-n-teal-8 bg-n-teal-3 text-n-teal-11'
      "
    >
      <div v-if="!findings.length" class="flex items-center gap-2">
        <span class="i-lucide-check size-4 shrink-0" />
        没查出问题：金额自洽、该填的条款都在、币种和价格都和这家客户以往一致。
      </div>
      <template v-else>
        <div class="flex items-center gap-2 mb-2 font-medium">
          <span class="i-lucide-triangle-alert size-4 shrink-0" />
          发出前请先核对这 {{ findings.length }} 处
        </div>
        <ul class="flex flex-col gap-1.5 pl-1">
          <li v-for="(f, i) in findings" :key="`hc-${i}`" class="flex gap-2">
            <span
              class="shrink-0 mt-0.5 size-1.5 rounded-full"
              :class="f.level === 'warn' ? 'bg-n-amber-9' : 'bg-n-slate-9'"
            />
            <span>
              <b class="font-medium">{{ f.title }}</b>
              <span class="text-n-slate-11"> — {{ f.detail }}</span>
            </span>
          </li>
        </ul>
      </template>
    </div>

    <!-- 文档本体：严格照 lib/pi/pi_template.xlsx 的版式与配色复刻（段标题灰底白字 #A6A6A6、
         字段标签浅底 #F3F6F9、表头 #E8EEF3、框线 #CDD6DF），所以预览 / PDF / 导出的 Excel 三者长一样。 -->
    <div
      v-else-if="doc"
      ref="docRef"
      class="p-6 overflow-x-auto bg-white border rounded-lg sm:p-8 border-n-weak"
    >
      <CrmPiDocument :doc="doc" />
    </div>
  </Dialog>
</template>
