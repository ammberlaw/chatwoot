<script setup>
import { ref } from 'vue';
import { computed, nextTick, watch } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MesImageLightbox from 'dashboard/components-next/mes/MesImageLightbox.vue';
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
  // [{ label, key, align, type, wrap }]
  //   type: 'images' → 渲染缩略图（值是 [{url, filename}]），点开在页内放大
  //   wrap: true     → 这列是长文本（规格型号/备注），给个宽度区间让它正常折行；
  //                    其余列一律不折行——中文可以在任意字之间断开，列一窄就被压成
  //                    「15.6\n寸背\n包屏」这种逐字竖排，根本没法看。
  itemColumns: { type: Array, default: () => [] },
  items: { type: Array, default: () => [] },
  // 附件分组：[{ label, kind: 'image'|'video'|'file', files: [{ filename, url }] }]。
  attachments: { type: Array, default: () => [] },
  // 弹窗宽度档（列多的详情如采购单可传更大，如 '5xl'）。
  width: { type: String, default: '2xl' },
  // 藏掉通用「打印」。入库单/领料单/出库单各自有照原版做的票面（打印入库单…），
  // 通用打印只是把弹窗内容照搬出来，两个按钮并排会让人印错那张。
  hidePrint: { type: Boolean, default: false },
});

const dialogRef = ref(null);
const contentRef = ref(null);
const lightboxRef = ref(null);

// 图片列不进 Excel：导出的是一张二维表，塞进去只会是 [object Object]。
// 导出图片/打印走的是 DOM 截图，缩略图自然就在里面，不用特殊处理。
const exportColumns = computed(() =>
  props.itemColumns.filter(c => c.type !== 'images')
);

// ── 明细表横向滚动 ──────────────────────────────────────────
// 列多的单（采购单 14 列）在弹窗里放不下。既给滑条、也给左右跳转按钮：
// 底部那根细横条用鼠标很难拖（Amber 反馈过），点一下翻一屏才是顺手的那个。
const itemScrollRef = ref(null);
const canScrollLeft = ref(false);
const canScrollRight = ref(false);

const syncScrollState = () => {
  const el = itemScrollRef.value;
  if (!el) return;
  canScrollLeft.value = el.scrollLeft > 1;
  // 留 1px 容差：缩放比例不是整数时 scrollLeft + clientWidth 到不了精确的 scrollWidth，
  // 严格相等会让「已经到底了」的右箭头一直亮着。
  canScrollRight.value = el.scrollLeft + el.clientWidth < el.scrollWidth - 1;
};

// 翻一屏留一点重叠（0.8），不然翻过去完全看不到上一屏的列，对不上是哪一行。
const scrollItems = dir => {
  const el = itemScrollRef.value;
  if (!el) return;
  el.scrollBy({ left: dir * el.clientWidth * 0.8, behavior: 'smooth' });
};

// 单据是弹窗打开后才填进来的，内容变了要重算（否则箭头按首次渲染的空表判断＝不出现）。
watch(
  () => [props.items, props.itemColumns],
  () => nextTick(syncScrollState),
  { deep: true, immediate: true }
);
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
      itemColumns: exportColumns.value,
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
    <!-- 导出/打印挂标题行右侧（Dialog 的 headerActions）：原先单起一排右对齐，
         既和右上角 ✕ 对不齐，最右那颗还会被 ✕ 压住半截。 -->
    <template #headerActions>
      <div class="flex gap-2 shrink-0">
        <!-- 调用方可以再挂自己的按钮（如入库单的「打印入库单」票面） -->
        <slot name="headerActions" />
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
          v-if="!hidePrint"
          label="打印"
          variant="outline"
          color="slate"
          size="sm"
          @click="printDoc"
        />
      </div>
    </template>
    <div class="flex flex-col gap-4 text-sm">
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
            <button
              v-for="(f, fi) in grp.files"
              :key="f.url"
              type="button"
              :title="f.filename"
              @click="lightboxRef?.open(grp.files, fi)"
            >
              <img
                :src="f.url"
                :alt="f.filename"
                class="object-contain border rounded-lg h-28 w-28 shrink-0 border-n-weak bg-n-alpha-1 hover:opacity-90"
              />
            </button>
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

        <div v-if="itemColumns.length" class="pt-2 border-t border-n-weak">
          <div v-if="itemsTitle" class="mb-2 text-heading-3 text-n-slate-12">
            {{ itemsTitle }}（{{ items.length }} 项）
          </div>
          <!-- 标题挪到滚动容器外：否则横向滚的时候标题会跟着跑出视野 -->
          <div class="relative">
            <div
              ref="itemScrollRef"
              class="overflow-x-auto"
              @scroll="syncScrollState"
            >
              <!-- w-max + min-w-full：列按自身内容取宽，撑不下就让外层容器横向滚，
               而不是把每一列压到逐字换行。 -->
              <table class="text-sm w-max min-w-full">
                <thead>
                  <tr class="text-left text-n-slate-11 border-b border-n-weak">
                    <!-- 序号：几十行料时口头对单要说「第几行」，没有序号只能数（反馈点名要加） -->
                    <th class="w-10 px-2 py-2 font-medium">#</th>
                    <th
                      v-for="c in itemColumns"
                      :key="c.key"
                      class="px-2 py-2 font-medium whitespace-nowrap"
                      :class="[
                        c.align === 'right' ? 'text-right' : '',
                        c.wrap ? 'min-w-[11rem]' : '',
                      ]"
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
                      class="px-2 py-2 align-top tabular-nums text-n-slate-10"
                    >
                      {{ i + 1 }}
                    </td>
                    <td
                      v-for="c in itemColumns"
                      :key="c.key"
                      class="px-2 py-2 align-top text-n-slate-12"
                      :class="[
                        c.align === 'right' ? 'text-right' : '',
                        c.wrap
                          ? 'min-w-[11rem] max-w-[18rem]'
                          : 'whitespace-nowrap',
                      ]"
                    >
                      <!-- 图片列：点缩略图在页内放大，不另开标签页 -->
                      <span
                        v-if="c.type === 'images'"
                        class="inline-flex flex-wrap items-center gap-1"
                      >
                        <button
                          v-for="(f, fi) in it[c.key] || []"
                          :key="f.id || f.url"
                          type="button"
                          :title="f.filename || f.name"
                          @click="lightboxRef?.open(it[c.key], fi)"
                        >
                          <img
                            :src="f.url"
                            :alt="f.filename || f.name"
                            class="object-contain border rounded size-10 shrink-0 border-n-weak bg-n-alpha-1 hover:opacity-80"
                          />
                        </button>
                        <span
                          v-if="!(it[c.key] || []).length"
                          class="text-n-slate-10"
                        >
                          —
                        </span>
                      </span>
                      <template v-else>{{ disp(it[c.key]) }}</template>
                    </td>
                  </tr>
                  <tr v-if="!items.length">
                    <td
                      :colspan="itemColumns.length + 1"
                      class="px-2 py-6 text-center text-n-slate-11"
                    >
                      无明细
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <!-- 左右跳转：只在真的还能往那边滚时出现，点一下翻一屏 -->
            <button
              v-show="canScrollLeft"
              type="button"
              class="absolute left-0 z-10 flex items-center justify-center border rounded-full shadow-md -translate-y-1/2 size-8 top-1/2 border-n-weak bg-n-solid-1 text-n-slate-11 hover:text-n-slate-12"
              title="向左翻一屏"
              @click="scrollItems(-1)"
            >
              <span class="i-lucide-chevron-left size-4" />
            </button>
            <button
              v-show="canScrollRight"
              type="button"
              class="absolute right-0 z-10 flex items-center justify-center border rounded-full shadow-md -translate-y-1/2 size-8 top-1/2 border-n-weak bg-n-solid-1 text-n-slate-11 hover:text-n-slate-12"
              title="向右翻一屏"
              @click="scrollItems(1)"
            >
              <span class="i-lucide-chevron-right size-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- 明细之后的补充区：给调用方挂本单独有的内容（如采购单的内部附图）。
           没传就不占位、不画分隔线。 -->
      <div v-if="$slots.extra" class="flex flex-col gap-2">
        <slot name="extra" />
      </div>

      <!-- 看图层：就地渲染（不 teleport），跟 <dialog> 一起在顶层才不会被它盖住 -->
      <MesImageLightbox ref="lightboxRef" />

      <!-- 底部操作区：给调用方放「通过/驳回」这类当场能办的动作，
           免得看完明细还要关掉弹窗回列表找按钮。没传就不占位。
           钉在弹窗底部——明细多的单（十几项物料）不钉住就得一路滚到底才看得到按钮。 -->
      <div
        v-if="$slots.actions"
        class="sticky bottom-0 flex flex-wrap items-center justify-end gap-2 py-3 -mb-4 border-t bg-n-solid-1 border-n-weak"
      >
        <slot name="actions" />
      </div>
    </div>
  </Dialog>
</template>
