<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  exportNodeToJpg,
  exportDataToExcel,
  printNode,
} from 'dashboard/helper/mesExport';

// 通用只读详情弹窗：抬头字段网格 +（可选）明细表。各环节列表复用。
const props = defineProps({
  title: { type: String, default: '明细' },
  // [{ label, value }]
  fields: { type: Array, default: () => [] },
  itemsTitle: { type: String, default: '' },
  // [{ label, key, align }]
  itemColumns: { type: Array, default: () => [] },
  items: { type: Array, default: () => [] },
  // 附件分组：[{ label, kind: 'image'|'video'|'file', files: [{ filename, url }] }]。
  attachments: { type: Array, default: () => [] },
  // 弹窗宽度档（列多的详情如采购单可传更大，如 '5xl'）。
  width: { type: String, default: '2xl' },
});

const dialogRef = ref(null);
const contentRef = ref(null);
defineExpose({
  open: () => dialogRef.value?.open(),
  close: () => dialogRef.value?.close(),
});

const disp = v => (v === null || v === undefined || v === '' ? '—' : v);

const exportExcel = () =>
  exportDataToExcel(
    {
      title: props.title,
      fields: props.fields,
      itemColumns: props.itemColumns,
      items: props.items,
    },
    props.title
  );
const exportJpg = () => exportNodeToJpg(contentRef.value, props.title);
const printDoc = () => printNode(contentRef.value, props.title);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :width="width"
    overflow-y-auto
    :show-confirm-button="false"
    cancel-button-label="关闭"
    :title="title"
  >
    <div class="flex flex-col gap-4 text-sm">
      <div class="flex justify-end gap-2">
        <Button
          label="导出 Excel"
          variant="outline"
          color="slate"
          size="sm"
          @click="exportExcel"
        />
        <Button
          label="导出图片"
          variant="outline"
          color="slate"
          size="sm"
          @click="exportJpg"
        />
        <Button
          label="打印"
          variant="outline"
          color="slate"
          size="sm"
          @click="printDoc"
        />
      </div>
      <div ref="contentRef" class="flex flex-col gap-4 p-4 bg-white rounded-lg">
        <div class="grid grid-cols-3 gap-x-4 gap-y-3">
          <div v-for="f in fields" :key="f.label" class="flex flex-col">
            <span class="text-xs text-n-slate-10">{{ f.label }}</span>
            <span class="text-n-slate-12">{{ disp(f.value) }}</span>
          </div>
        </div>

        <!-- 附件区：照片缩略图 / 视频内联 / 文件下载链接 -->
        <div
          v-for="grp in attachments"
          :key="grp.label"
          class="pt-2 border-t border-n-weak"
        >
          <div
            class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ grp.label }}（{{ grp.files.length }}）
          </div>
          <div v-if="grp.kind === 'image'" class="flex flex-wrap gap-2">
            <a
              v-for="f in grp.files"
              :key="f.url"
              :href="f.url"
              target="_blank"
              rel="noopener noreferrer"
              :title="f.filename"
            >
              <img
                :src="f.url"
                :alt="f.filename"
                class="object-cover border rounded-lg h-28 w-28 border-n-weak hover:opacity-90"
              />
            </a>
          </div>
          <div v-else-if="grp.kind === 'video'" class="flex flex-wrap gap-3">
            <video
              v-for="f in grp.files"
              :key="f.url"
              :src="f.url"
              controls
              class="border rounded-lg h-44 border-n-weak"
            />
          </div>
          <div v-else class="flex flex-col gap-1">
            <a
              v-for="f in grp.files"
              :key="f.url"
              :href="f.url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1.5 text-n-iris-11 hover:underline w-fit"
            >
              <span class="i-lucide-paperclip size-4 shrink-0" />
              {{ f.filename }}
            </a>
          </div>
        </div>

        <div
          v-if="itemColumns.length"
          class="pt-2 overflow-x-auto border-t border-n-weak"
        >
          <div
            v-if="itemsTitle"
            class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ itemsTitle }}（{{ items.length }} 项）
          </div>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th
                  v-for="c in itemColumns"
                  :key="c.key"
                  class="px-2 py-2 font-medium whitespace-nowrap"
                  :class="c.align === 'right' ? 'text-right' : ''"
                >
                  {{ c.label }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(it, i) in items"
                :key="i"
                class="border-b border-n-weak"
              >
                <td
                  v-for="c in itemColumns"
                  :key="c.key"
                  class="px-2 py-2 text-n-slate-12"
                  :class="c.align === 'right' ? 'text-right' : ''"
                >
                  {{ disp(it[c.key]) }}
                </td>
              </tr>
              <tr v-if="!items.length">
                <td
                  :colspan="itemColumns.length"
                  class="px-2 py-6 text-center text-n-slate-11"
                >
                  无明细
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </Dialog>
</template>
