<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PriceListAPI from 'dashboard/api/crm/priceLists';
import { LocalStorage } from 'shared/helpers/localStorage';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AttachmentPreview from 'dashboard/components-next/attachment/AttachmentPreview.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 标准价目表：主管/财务按版本维护，业务员只读最新已发布版并可导出 PDF。
// 没有现成价的定制件走「定制报价」向上要价，两边是一对的。
// 一次改价 = 发一版新的（原来那张 Excel 十个 sheet 就是十版），业务员永远只看到一张有效表。
const CURRENCIES = [
  { value: 'USD', label: '美元 USD' },
  { value: 'CNY', label: '人民币 CNY' },
  { value: 'EUR', label: '欧元 EUR' },
];
const SYMBOLS = { USD: '$', CNY: '¥', EUR: '€' };

const allVersions = ref([]); // 全部产品线的版本，前端按产品线切分
const productLines = ref([]);
// 产品线多了以后每次都从第一条开始翻很烦，记住上次看的那条。
const LINE_KEY = 'crm:price-list-line';
const activeLine = ref(LocalStorage.get(LINE_KEY) || '');
const activeId = ref(null);
const detail = ref(null);
const canManage = ref(false);
const loading = ref(true);
const saving = ref(false);
const editing = ref(false);
const form = ref(null); // 编辑态的整表副本，取消即丢弃

const symbol = computed(() => SYMBOLS[detail.value?.currency] || '');
const columns = computed(() => detail.value?.columns || []);
// 有图才显示图片列；编辑态一律显示，方便给没图的行补图。
// 列多的表（条形屏 10 列 + 图片）横向要滚，允许各人按需要收起几列。
// 按「产品线 + 列名」记住，换版本不会错位。
const COLS_KEY = 'crm:price-list-hidden-cols';
const hiddenCols = ref(new Set());
const showColumnPanel = ref(false);
const readHidden = line => {
  const all = LocalStorage.get(COLS_KEY) || {};
  return new Set(all[line] || []);
};
const writeHidden = () => {
  const all = LocalStorage.get(COLS_KEY) || {};
  all[activeLine.value] = [...hiddenCols.value];
  LocalStorage.set(COLS_KEY, all);
};
const isHidden = label => hiddenCols.value.has(label);
const toggleColumn = label => {
  const next = new Set(hiddenCols.value);
  if (next.has(label)) next.delete(label);
  else next.add(label);
  hiddenCols.value = next;
  writeHidden();
};
const showAllColumns = () => {
  hiddenCols.value = new Set();
  writeHidden();
};

const showImageColumn = computed(
  () => editing.value || (!!detail.value?.has_images && !isHidden('图片'))
);
// 编辑态显示全部列——不然改不到被收起来的那几列。
// 必须带上原始下标：values 是按原始列顺序存的，过滤后用新下标取值会错位。
const visibleColumns = computed(() =>
  columns.value
    .map((c, idx) => ({ ...c, idx }))
    .filter(c => editing.value || !isHidden(c.label))
);
const previewFile = ref(null);
const openPreview = item => {
  if (!item.image_url) return;
  previewFile.value = {
    filename: `${item.values?.[0] || '产品图'}.png`,
    url: item.image_url,
  };
};
// 当前产品线下的版本（一条产品线一条独立的版本链）。
const versions = computed(() =>
  allVersions.value.filter(v => v.product_line === activeLine.value)
);
const lineOptions = computed(() =>
  productLines.value.map(l => ({ value: l, label: l }))
);
const versionOptions = computed(() =>
  versions.value.map(v => ({
    value: String(v.id),
    label: `${v.effective_on || '未定日期'} · ${v.status_label}`,
  }))
);
// 价格列：能当数字读的补币种符号；填「面议」这类文字就原样显示。
const cellText = (value, type) => {
  const text = (value ?? '').toString().trim();
  if (type !== 'price' || !text) return text;
  const num = Number(text.replace(/[$¥,\s]/g, ''));
  return Number.isNaN(num) ? text : `${symbol.value}${num.toFixed(2)}`;
};

const loadVersions = async () => {
  const { data } = await PriceListAPI.get();
  allVersions.value = data.payload || [];
  productLines.value = data.product_lines || [];
  canManage.value = data.can_manage === true;
};

const loadDetail = async id => {
  if (!id) {
    detail.value = null;
    return;
  }
  const { data } = await PriceListAPI.show(id);
  detail.value = data;
  activeId.value = data.id;
};

// 进某条产品线时默认停在已发布那版（业务员看到的就是它），没有就取最新一条。
const pickVersion = () => {
  const list = versions.value;
  return list.find(v => v.status === 'PUBLISHED') || list[0];
};

// ── 跨产品线搜型号：知道型号但不知道归在哪条线时用 ──
const searchQuery = ref('');
const searchResults = ref([]);
const searching = ref(false);
const inSearch = computed(() => searchQuery.value.trim().length >= 2);
let searchTimer = null;
const runSearch = async () => {
  if (!inSearch.value) {
    searchResults.value = [];
    return;
  }
  searching.value = true;
  try {
    const { data } = await PriceListAPI.search(searchQuery.value.trim());
    searchResults.value = data.payload || [];
  } catch (error) {
    searchResults.value = [];
  } finally {
    searching.value = false;
  }
};
const onSearchInput = () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(runSearch, 300);
};
// 从搜索结果跳到那条产品线
const gotoResult = async row => {
  searchQuery.value = '';
  searchResults.value = [];
  activeLine.value = row.product_line;
  hiddenCols.value = readHidden(row.product_line);
  await loadDetail(row.list_id);
};
// 搜索结果里价格列的取值
const priceCells = row =>
  row.columns
    .map((c, i) => ({ ...c, value: row.values[i] }))
    .filter(c => c.type === 'price' && c.value);
const textSummary = row =>
  row.columns
    .map((c, i) => ({ type: c.type, value: row.values[i] }))
    .filter(c => c.type !== 'price' && c.value)
    .map(c => c.value)
    .join(' · ');

// ── 与上一版对比 ──
const diffDialogRef = ref(null);
const diffData = ref(null);
const diffLoading = ref(false);
const openDiff = async () => {
  diffData.value = null;
  diffLoading.value = true;
  diffDialogRef.value?.open();
  try {
    const { data } = await PriceListAPI.diff(activeId.value);
    diffData.value = data;
  } catch (error) {
    useAlert(error?.response?.data?.error || '取不到对比数据');
    diffDialogRef.value?.close();
  } finally {
    diffLoading.value = false;
  }
};

const load = async (keepLine = true) => {
  loading.value = true;
  try {
    await loadVersions();
    if (!keepLine || !productLines.value.includes(activeLine.value)) {
      activeLine.value = productLines.value[0] || '';
    }
    hiddenCols.value = readHidden(activeLine.value);
    await loadDetail(pickVersion()?.id);
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载标准价目表失败');
  } finally {
    loading.value = false;
  }
};

const onSwitchVersion = async id => {
  editing.value = false;
  await loadDetail(Number(id));
};

const onSwitchLine = async line => {
  editing.value = false;
  activeLine.value = line;
  hiddenCols.value = readHidden(line);
  showColumnPanel.value = false;
  LocalStorage.set(LINE_KEY, line);
  await loadDetail(pickVersion()?.id);
};

// ── 编辑 ──
const startEdit = () => {
  form.value = {
    title: detail.value.title,
    effective_on: detail.value.effective_on,
    currency: detail.value.currency,
    columns: (detail.value.columns || []).map(c => ({ ...c })),
    header_note: detail.value.header_note || '',
    rules_note: detail.value.rules_note || '',
    footer_name: detail.value.footer_name || '',
    items: (detail.value.items || []).map(i => ({
      id: i.id,
      values: (detail.value.columns || []).map((_, idx) =>
        (i.values?.[idx] ?? '').toString()
      ),
      remark: i.remark || '',
      image_url: i.image_url,
      pendingImage: null, // 保存成功后再上传（新行要先有 id）
      pendingDocId: null,
    })),
  };
  editing.value = true;
};

const cancelEdit = () => {
  editing.value = false;
  form.value = null;
};

const addRow = () =>
  form.value.items.push({
    id: null,
    values: form.value.columns.map(() => ''),
    remark: '',
    image_url: null,
    pendingImage: null,
    pendingDocId: null,
  });

// 行内选图：先记在行上，保存后按顺序传（新行这时才有 id）。
const rowFileInput = ref(null);
const pendingRowIndex = ref(null);

// 选图弹窗：优先从公司文档里挑（产品图多半已经传过），也可以传本地文件。
const imageDialogRef = ref(null);
const docImages = ref([]);
const docImageQuery = ref('');
const docImagesLoading = ref(false);
const docSections = ref([]);
const activeDocSection = ref('');
const docSectionOptions = computed(() => [
  { value: '', label: '全部板块' },
  ...docSections.value.map(s => ({ value: String(s.id), label: s.name })),
]);
const loadDocImages = async () => {
  docImagesLoading.value = true;
  try {
    const { data } = await PriceListAPI.docImages({
      q: docImageQuery.value,
      sectionId: activeDocSection.value,
    });
    docImages.value = data.payload || [];
    docSections.value = data.sections || [];
  } catch (error) {
    docImages.value = [];
  } finally {
    docImagesLoading.value = false;
  }
};
const onSwitchDocSection = section => {
  activeDocSection.value = section;
  loadDocImages();
};
const pickRowImage = async i => {
  pendingRowIndex.value = i;
  docImageQuery.value = '';
  imageDialogRef.value?.open();
  await loadDocImages();
  // 产品图基本都在「设计资料」，默认停在那儿，省得每次自己切。
  const design = docSections.value.find(s => s.name.includes('设计'));
  if (design && !activeDocSection.value) {
    activeDocSection.value = String(design.id);
    await loadDocImages();
  }
};
const pickLocalFile = () => rowFileInput.value?.click();
// 选中公司文档里的图：已有 id 的行直接挂，新行先记着、保存后再挂。
const chooseDocImage = async img => {
  const row = form.value.items[pendingRowIndex.value];
  if (!row) return;
  row.image_url = img.url;
  row.pendingImage = null;
  row.pendingDocId = img.id;
  imageDialogRef.value?.close();
  if (!row.id) return;
  try {
    const { data } = await PriceListAPI.imageFromDoc(
      activeId.value,
      row.id,
      img.id
    );
    row.image_url = data.image_url;
    row.pendingDocId = null;
  } catch (error) {
    useAlert('挂图失败，请重试');
  }
};
const onRowImagePicked = event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file || pendingRowIndex.value === null) return;
  const row = form.value.items[pendingRowIndex.value];
  row.pendingImage = file;
  row.pendingDocId = null;
  row.image_url = URL.createObjectURL(file); // 本地预览
  imageDialogRef.value?.close();
};
// 加列/删列要同步每一行的值，否则值和列错位。
const addColumn = () => {
  form.value.columns.push({ label: '新列', type: 'text' });
  form.value.items.forEach(r => r.values.push(''));
};
const removeColumn = i => {
  form.value.columns.splice(i, 1);
  form.value.items.forEach(r => r.values.splice(i, 1));
};
const COLUMN_TYPES = [
  { value: 'text', label: '文本' },
  { value: 'price', label: '价格' },
];
const removeRow = i => form.value.items.splice(i, 1);
const moveRow = (i, delta) => {
  const target = i + delta;
  if (target < 0 || target >= form.value.items.length) return;
  const [row] = form.value.items.splice(i, 1);
  form.value.items.splice(target, 0, row);
};

const uploadPendingImages = async saved => {
  const rows = form.value.items;
  await Promise.all(
    rows.map((row, i) => {
      const id = saved.items?.[i]?.id;
      if (!id) return null;
      if (row.pendingImage) {
        return PriceListAPI.uploadImage(activeId.value, id, row.pendingImage);
      }
      if (row.pendingDocId) {
        return PriceListAPI.imageFromDoc(activeId.value, id, row.pendingDocId);
      }
      return null;
    })
  );
};

const save = async ({ publish = false } = {}) => {
  saving.value = true;
  try {
    const { data: saved } = await PriceListAPI.update(activeId.value, {
      price_list: form.value,
    });
    await uploadPendingImages(saved);
    if (publish) await PriceListAPI.publish(activeId.value);
    editing.value = false;
    form.value = null;
    await load();
    useAlert(publish ? '已发布，业务员现在看到的是这版' : '已保存');
  } catch (error) {
    useAlert(error?.response?.data?.error || error?.message || '保存失败');
  } finally {
    saving.value = false;
  }
};

// ── 从公司现成的 Excel 导入（一个 sheet 建一条产品线草稿）──
const fileInput = ref(null);
const importing = ref(false);
const pickFile = () => fileInput.value?.click();
const onFilePicked = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  importing.value = true;
  try {
    const { data } = await PriceListAPI.importFile(file);
    await load(false);
    const first = data.imported?.[0];
    if (first) {
      activeLine.value = first.product_line;
      await loadDetail(first.id);
    }
    useAlert(
      `导入 ${data.imported.length} 条产品线：${data.imported
        .map(i => `${i.product_line}(${i.rows}行)`)
        .join('、')}`
    );
  } catch (error) {
    useAlert(error?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
};

// ── 新建一条产品线的报价单 ──
const createDialogRef = ref(null);
const DEFAULT_COLUMNS = [
  { label: '型号', type: 'text' },
  { label: '产品规格', type: 'text' },
  { label: '10台内', type: 'price' },
  { label: '11-199', type: 'price' },
  { label: '200以上', type: 'price' },
];
const newForm = ref({
  product_line: '',
  title: '',
  effective_on: '',
  currency: 'USD',
  columns: DEFAULT_COLUMNS.map(c => ({ ...c })),
});
const { isDirty, markPristine } = useDirtyGuard(() => newForm.value);
const openCreate = () => {
  newForm.value = {
    product_line: '',
    title: '',
    effective_on: new Date().toISOString().slice(0, 10),
    currency: 'USD',
    columns: DEFAULT_COLUMNS.map(c => ({ ...c })),
  };
  markPristine();
  createDialogRef.value?.open();
};
const submitCreate = async () => {
  if (!newForm.value.product_line.trim() || !newForm.value.title.trim()) {
    useAlert('产品线和标题都要填');
    return;
  }
  try {
    const { data } = await PriceListAPI.create({ price_list: newForm.value });
    createDialogRef.value?.close();
    await loadVersions();
    activeLine.value = data.product_line;
    await loadDetail(data.id);
    startEdit();
  } catch (error) {
    useAlert(error?.response?.data?.error || '新建失败');
  }
};

// 新版本一律从当前版复制——二十几行规格重录一遍不现实。
const createVersion = async () => {
  try {
    const { data } = await PriceListAPI.duplicate(activeId.value);
    await loadVersions();
    activeLine.value = data.product_line;
    await loadDetail(data.id);
    startEdit();
    useAlert('已复制为草稿，改完价格再发布');
  } catch (error) {
    useAlert(error?.response?.data?.error || '新建版本失败');
  }
};

const publishCurrent = async () => {
  try {
    await PriceListAPI.publish(activeId.value);
    await load();
    useAlert('已发布');
  } catch (error) {
    useAlert(error?.response?.data?.error || '发布失败');
  }
};

const removeVersion = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('删除这个草稿版本？')) return;
  try {
    await PriceListAPI.delete(activeId.value);
    await load();
    useAlert('已删除');
  } catch (error) {
    useAlert(error?.response?.data?.error || '删除失败');
  }
};

// 接口走 api_access_token 头鉴权，浏览器直接开链接不带头会报未登录，
// 所以用 axios 取回 blob 再本地触发下载（与 PI 导出同款）。
const exporting = ref(false);
const exportPdf = async () => {
  exporting.value = true;
  try {
    const { data } = await PriceListAPI.exportPdf(activeId.value);
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    const date = (detail.value.effective_on || '')
      .replace(/-0?/g, '.')
      .replace(/^\./, '');
    a.download = `${date}${detail.value.title}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert('导出失败，请稍后重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(load);
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="w-full px-4 py-4 mx-auto max-w-7xl sm:px-8 sm:py-6 [.theme-classic_&]:max-w-none [.theme-classic_&]:lg:!px-8"
    >
      <div
        class="flex items-center justify-between mb-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:mb-6 [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center"
      >
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
          标准价目表
        </h1>
        <div
          class="flex items-center gap-2 [.theme-classic_&]:flex-wrap [.theme-classic_&]:[&>button]:!rounded-xl [.theme-classic_&]:[&>button]:!border-[#e3e4df] [.theme-classic_&]:[&>button]:!outline-[#e3e4df] [.theme-classic_&]:[&>button]:!text-[#292b2b] [.theme-classic_&]:[&>button]:!bg-[#f7f8fa] [.theme-classic_&]:[&>button:last-child]:!bg-[#ffd34f] [.theme-classic_&]:[&>button:last-child]:!outline-transparent"
        >
          <template v-if="!editing">
            <Button
              :label="exporting ? '导出中…' : '导出 PDF'"
              variant="outline"
              size="sm"
              :disabled="!detail || exporting"
              @click="exportPdf"
            />
            <Button
              v-if="canManage"
              :label="importing ? '导入中…' : '从 Excel 导入'"
              variant="outline"
              size="sm"
              :disabled="importing"
              @click="pickFile"
            />
            <Button
              v-if="canManage"
              label="新建报价单"
              variant="outline"
              size="sm"
              @click="openCreate"
            />
            <Button
              v-if="detail"
              label="对比上一版"
              variant="outline"
              size="sm"
              icon="i-lucide-git-compare"
              @click="openDiff"
            />
            <template v-if="canManage && detail">
              <Button
                label="改价（新版本）"
                class="[.theme-classic_&]:!bg-[#ffd34f] [.theme-classic_&]:!border-[#ffd34f] [.theme-classic_&]:!outline-transparent [.theme-classic_&]:!font-bold"
                variant="outline"
                size="sm"
                @click="createVersion"
              />
              <Button
                v-if="detail.status === 'DRAFT'"
                label="编辑草稿"
                variant="outline"
                size="sm"
                @click="startEdit"
              />
              <Button
                v-if="detail.status === 'DRAFT'"
                label="发布"
                size="sm"
                color="iris"
                @click="publishCurrent"
              />
              <Button
                v-if="detail.status === 'DRAFT'"
                label="删除草稿"
                variant="outline"
                size="sm"
                color="ruby"
                @click="removeVersion"
              />
            </template>
          </template>
          <template v-else>
            <Button
              label="取消"
              variant="outline"
              size="sm"
              @click="cancelEdit"
            />
            <Button
              label="保存草稿"
              variant="outline"
              size="sm"
              :disabled="saving"
              @click="save()"
            />
            <Button
              label="保存并发布"
              size="sm"
              color="iris"
              :disabled="saving"
              @click="save({ publish: true })"
            />
          </template>
        </div>
      </div>

      <div v-if="loading" class="py-12 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <div
        v-else-if="!detail"
        class="py-12 text-sm text-center text-n-slate-10"
      >
        还没有标准价目表。
        <template v-if="canManage">
          点右上角「新建报价单」建第一条产品线。
        </template>
      </div>

      <template v-else>
        <!-- 版本条 -->
        <div
          class="flex flex-wrap items-center gap-3 px-4 py-3 mb-4 text-sm rounded-xl bg-n-alpha-1 [.theme-classic_&]:rounded-2xl [.theme-classic_&]:bg-[#f7f8fa] [.theme-classic_&]:p-5 [.theme-classic_&]:gap-x-3 [.theme-classic_&]:gap-y-3 [.theme-classic_&]:[&>span:first-child]:font-semibold"
        >
          <span class="text-n-slate-11">产品线</span>
          <SelectCard
            :model-value="activeLine"
            :options="lineOptions"
            trigger-class="w-40 h-9 [.theme-classic_&]:!rounded-xl [.theme-classic_&]:!border-0 [.theme-classic_&]:!bg-white [.theme-classic_&]:!font-semibold"
            :disabled="editing"
            @update:model-value="onSwitchLine"
          />
          <span class="text-n-slate-11">版本</span>
          <SelectCard
            :model-value="String(activeId)"
            :options="versionOptions"
            trigger-class="w-56 h-9 [.theme-classic_&]:!rounded-xl [.theme-classic_&]:!border-0 [.theme-classic_&]:!bg-white"
            :disabled="editing"
            @update:model-value="onSwitchVersion"
          />
          <span
            class="px-2 py-0.5 text-xs rounded-full"
            :class="
              detail.status === 'PUBLISHED'
                ? 'bg-n-teal-3 text-n-teal-11'
                : detail.status === 'DRAFT'
                  ? 'bg-n-amber-3 text-n-amber-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            {{ detail.status_label }}
          </span>
          <span class="text-n-slate-11">
            共
            <b class="text-n-slate-12">{{ detail.items?.length || 0 }}</b>
            个型号 · 币种 {{ detail.currency }}
          </span>
          <span
            v-if="detail.published_by_name"
            class="text-xs text-n-slate-10 [.theme-classic_&]:hidden [.theme-classic_&]:2xl:block"
          >
            由 {{ detail.published_by_name }} 发布
          </span>
          <Input
            v-if="!editing"
            v-model="searchQuery"
            placeholder="跨产品线搜型号"
            class="ml-auto w-52 [.theme-classic_&]:w-40"
            @input="onSearchInput"
          />
          <div v-if="!editing" class="relative">
            <Button
              :label="hiddenCols.size ? `列（收起 ${hiddenCols.size}）` : '列'"
              class="[.theme-classic_&]:!outline-[#dedfd9] [.theme-classic_&]:!text-[#292b2b] [.theme-classic_&]:!rounded-xl"
              variant="outline"
              size="sm"
              icon="i-lucide-columns-3"
              @click="showColumnPanel = !showColumnPanel"
            />
            <!-- 透明兜底层：点面板外面收起来，省掉一个全局 click 监听。 -->
            <div
              v-if="showColumnPanel"
              class="fixed inset-0 z-10"
              @click="showColumnPanel = false"
            />
            <div
              v-if="showColumnPanel"
              class="absolute right-0 z-20 flex flex-col gap-1 p-2 mt-1 border shadow-lg top-full w-52 rounded-xl border-n-weak bg-n-solid-1"
            >
              <label
                v-if="detail.has_images"
                class="flex items-center gap-2 px-2 py-1 text-sm rounded cursor-pointer hover:bg-n-alpha-1"
              >
                <input
                  type="checkbox"
                  :checked="!isHidden('图片')"
                  @change="toggleColumn('图片')"
                />
                图片
              </label>
              <label
                v-for="c in columns"
                :key="`vis-${c.label}`"
                class="flex items-center gap-2 px-2 py-1 text-sm rounded cursor-pointer hover:bg-n-alpha-1"
              >
                <input
                  type="checkbox"
                  :checked="!isHidden(c.label)"
                  @change="toggleColumn(c.label)"
                />
                {{ c.label }}
              </label>
              <button
                class="px-2 py-1 mt-1 text-xs text-left border-t text-n-slate-11 border-n-weak hover:text-n-slate-12"
                @click="showAllColumns"
              >
                全部显示
              </button>
            </div>
          </div>
        </div>

        <!-- 搜索结果：盖住原表格，点一条跳到那条产品线 -->
        <div
          v-if="inSearch"
          class="mb-4 overflow-hidden border rounded-xl border-n-weak"
        >
          <div
            class="flex items-center justify-between px-4 py-2 text-xs bg-n-alpha-1 text-n-slate-11"
          >
            <span>
              搜「{{ searchQuery }}」命中
              <b class="text-n-slate-12">{{ searchResults.length }}</b>
              条
            </span>
            <button
              class="underline hover:text-n-slate-12"
              @click="searchQuery = ''"
            >
              清除
            </button>
          </div>
          <div
            v-if="searching"
            class="py-8 text-sm text-center text-n-slate-10"
          >
            搜索中…
          </div>
          <div
            v-else-if="!searchResults.length"
            class="py-8 text-sm text-center text-n-slate-10"
          >
            没找到，换个型号或名称试试。
          </div>
          <template v-else>
            <button
              v-for="(row, i) in searchResults"
              :key="`sr-${i}`"
              class="flex items-center w-full gap-3 px-4 py-2 text-left border-t border-n-weak hover:bg-n-alpha-1 [.theme-classic_&]:border-[#edf0f2] [.theme-classic_&]:hover:bg-[#f7f8fa] [.theme-classic_&]:[&>td]:!py-5 [.theme-classic_&]:[&>td:first-child]:!font-bold [.theme-classic_&]:[&>td:first-child]:!text-[#202222]"
              @click="gotoResult(row)"
            >
              <img
                v-if="row.image_url"
                :src="row.image_url"
                class="object-contain w-12 h-9 rounded bg-n-alpha-1 shrink-0"
              />
              <span
                class="px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11 shrink-0"
              >
                {{ row.product_line }}
              </span>
              <span class="flex-1 text-sm truncate text-n-slate-12">
                {{ textSummary(row) }}
              </span>
              <span
                v-for="p in priceCells(row)"
                :key="p.label"
                class="text-xs whitespace-nowrap text-n-slate-11"
              >
                {{ p.label }}
                <b class="text-n-slate-12">{{ cellText(p.value, 'price') }}</b>
              </span>
            </button>
          </template>
        </div>

        <!-- 编辑态的表头信息 -->
        <div
          v-if="editing"
          class="grid grid-cols-1 gap-3 p-4 mb-4 border rounded-xl border-n-weak sm:grid-cols-3"
        >
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">标题</span>
            <Input v-model="form.title" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">生效日期（落款）</span>
            <DatePicker v-model="form.effective_on" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">币种</span>
            <SelectCard
              v-model="form.currency"
              :options="CURRENCIES"
              trigger-class="h-9"
            />
          </label>
          <div class="flex flex-col gap-2 sm:col-span-3">
            <span class="text-xs text-n-slate-11">
              列（价格类会带币种符号并右对齐）
            </span>
            <div class="flex flex-wrap items-end gap-2">
              <div
                v-for="(c, i) in form.columns"
                :key="`col-${i}`"
                class="flex items-center gap-1"
              >
                <Input v-model="c.label" class="w-32" />
                <SelectCard
                  v-model="c.type"
                  :options="COLUMN_TYPES"
                  trigger-class="w-20 h-9"
                />
                <Button
                  icon="i-lucide-x"
                  variant="ghost"
                  size="xs"
                  color="ruby"
                  @click="removeColumn(i)"
                />
              </div>
              <Button
                label="加一列"
                variant="outline"
                size="sm"
                icon="i-lucide-plus"
                @click="addColumn"
              />
            </div>
          </div>
          <label class="flex flex-col gap-1 sm:col-span-3">
            <span class="text-xs text-n-slate-11">表头备注（每行一条）</span>
            <textarea
              v-model="form.header_note"
              rows="3"
              class="px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">报价规则说明</span>
            <textarea
              v-model="form.rules_note"
              rows="3"
              class="px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">落款</span>
            <Input v-model="form.footer_name" />
          </label>
        </div>

        <!-- 只读态的表头备注 -->
        <div
          v-else-if="detail.header_note"
          class="px-1 py-2 mb-4 text-xs leading-6 whitespace-pre-line text-n-slate-12"
        >
          {{ detail.header_note }}
        </div>

        <!-- 价格表 -->
        <HScrollButtons />
        <div
          class="overflow-x-auto border rounded-xl border-n-weak [.theme-classic_&]:rounded-2xl [.theme-classic_&]:border-[#e8eaed]"
        >
          <table
            class="w-full text-sm [.theme-classic_&]:text-label [.theme-classic_&]:tabular-nums"
          >
            <thead
              class="bg-n-alpha-1 text-n-slate-11 [.theme-classic_&]:bg-white [.theme-classic_&]:text-[#292b2b] [.theme-classic_&]:[&_th]:py-4 [.theme-classic_&]:[&_th]:font-semibold [.theme-classic_&]:border-b [.theme-classic_&]:border-[#e8eaed]"
            >
              <tr>
                <th
                  v-if="showImageColumn"
                  class="px-3 py-3 font-medium text-left w-[84px] min-w-[84px] whitespace-nowrap"
                >
                  图片
                </th>
                <th
                  v-for="(c, i) in editing ? form.columns : visibleColumns"
                  :key="`h-${i}`"
                  class="px-4 py-3 font-medium whitespace-nowrap"
                  :class="
                    c.type === 'price'
                      ? 'text-right w-28 min-w-[92px]'
                      : 'text-left min-w-[96px]'
                  "
                >
                  {{ c.label }}
                </th>
                <th v-if="editing" class="px-2 py-3 w-28" />
              </tr>
            </thead>
            <tbody>
              <template v-if="!editing">
                <tr
                  v-for="item in detail.items"
                  :key="item.id"
                  class="border-t border-n-weak hover:bg-n-alpha-1"
                >
                  <td
                    v-if="showImageColumn"
                    class="px-3 py-2 w-[84px] min-w-[84px]"
                  >
                    <img
                      v-if="item.image_url"
                      :src="item.image_url"
                      class="object-contain w-[60px] h-11 rounded cursor-zoom-in bg-n-alpha-1"
                      @click="openPreview(item)"
                    />
                  </td>
                  <td
                    v-for="c in visibleColumns"
                    :key="`c-${item.id}-${c.idx}`"
                    class="px-4 py-3"
                    :class="
                      c.type === 'price'
                        ? 'text-right whitespace-nowrap text-n-slate-12 [.theme-classic_&]:font-semibold [.theme-classic_&]:text-heading-2'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ cellText(item.values?.[c.idx], c.type) }}
                  </td>
                </tr>
              </template>
              <template v-else>
                <tr
                  v-for="(row, ri) in form.items"
                  :key="`r-${ri}`"
                  class="border-t border-n-weak"
                >
                  <td
                    v-if="showImageColumn"
                    class="px-3 py-2 w-[84px] min-w-[84px]"
                  >
                    <img
                      v-if="row.image_url"
                      :src="row.image_url"
                      class="object-contain w-[60px] h-11 rounded cursor-pointer bg-n-alpha-1"
                      @click="pickRowImage(ri)"
                    />
                    <Button
                      v-else
                      icon="i-lucide-image-plus"
                      variant="outline"
                      size="xs"
                      @click="pickRowImage(ri)"
                    />
                  </td>
                  <td
                    v-for="(c, i) in form.columns"
                    :key="`e-${ri}-${i}`"
                    class="px-2 py-2"
                    :class="c.type === 'price' ? 'w-28' : ''"
                  >
                    <Input v-model="row.values[i]" :placeholder="c.label" />
                  </td>
                  <td class="px-2 py-2 text-right whitespace-nowrap">
                    <Button
                      icon="i-lucide-chevron-up"
                      variant="ghost"
                      size="xs"
                      @click="moveRow(ri, -1)"
                    />
                    <Button
                      icon="i-lucide-chevron-down"
                      variant="ghost"
                      size="xs"
                      @click="moveRow(ri, 1)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      size="xs"
                      color="ruby"
                      @click="removeRow(ri)"
                    />
                  </td>
                </tr>
              </template>
              <tr v-if="!editing && !detail.items?.length">
                <td
                  :colspan="visibleColumns.length + (showImageColumn ? 1 : 0)"
                  class="px-4 py-12 text-center text-n-slate-10"
                >
                  这一版还没有型号。
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="editing" class="mt-3">
          <Button
            label="添加一行"
            variant="outline"
            size="sm"
            icon="i-lucide-plus"
            @click="addRow"
          />
        </div>

        <div
          v-if="!editing && detail.rules_note"
          class="mt-4 text-xs leading-6 whitespace-pre-line text-n-slate-11 [.theme-classic_&]:rounded-xl [.theme-classic_&]:bg-[#f7f8fa] [.theme-classic_&]:px-4 [.theme-classic_&]:py-3 [.theme-classic_&]:text-label-small"
        >
          {{ detail.rules_note }}
        </div>
        <div
          v-if="!editing && detail.footer_name"
          class="mt-4 mb-2 text-xs text-right text-n-slate-11"
        >
          {{ detail.footer_name }}
          <br />
          {{ detail.effective_on }}
        </div>
      </template>
    </div>

    <input
      ref="fileInput"
      type="file"
      accept=".xlsx"
      class="hidden"
      @change="onFilePicked"
    />
    <input
      ref="rowFileInput"
      type="file"
      accept="image/*"
      class="hidden"
      @change="onRowImagePicked"
    />

    <AttachmentPreview :file="previewFile" @close="previewFile = null" />

    <Dialog
      ref="diffDialogRef"
      width="xl"
      title="与上一版对比"
      :show-confirm-button="false"
    >
      <div v-if="diffLoading" class="py-10 text-sm text-center text-n-slate-10">
        对比中…
      </div>
      <div v-else-if="diffData" class="flex flex-col gap-4">
        <p class="text-sm text-n-slate-11">
          {{ diffData.previous.effective_on }} →
          {{ diffData.current.effective_on }}｜改价
          <b class="text-n-slate-12">{{ diffData.changed.length }}</b>
          项 · 新增
          <b class="text-n-teal-11">{{ diffData.added.length }}</b>
          项 · 下架
          <b class="text-n-ruby-11">{{ diffData.removed.length }}</b>
          项
        </p>

        <div v-if="diffData.changed.length" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-11">改价</span>
          <div
            v-for="c in diffData.changed"
            :key="`ch-${c.key}`"
            class="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-sm border rounded-lg border-n-weak"
          >
            <b class="text-n-slate-12">{{ c.key }}</b>
            <span
              v-for="d in c.deltas"
              :key="d.label"
              class="text-xs"
              :class="d.now > d.was ? 'text-n-ruby-11' : 'text-n-teal-11'"
            >
              {{ d.label }} {{ d.was }} → {{ d.now }}
              <template v-if="d.percent !== null">
                （{{ d.percent > 0 ? '+' : '' }}{{ d.percent }}%）
              </template>
            </span>
          </div>
        </div>

        <div v-if="diffData.added.length" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-teal-11">新增</span>
          <span
            v-for="a in diffData.added"
            :key="`ad-${a.key}`"
            class="px-3 py-1.5 text-sm border rounded-lg border-n-teal-6 text-n-slate-12"
          >
            {{ a.key }}
          </span>
        </div>

        <div v-if="diffData.removed.length" class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-ruby-11">下架</span>
          <span
            v-for="r in diffData.removed"
            :key="`rm-${r.key}`"
            class="px-3 py-1.5 text-sm border rounded-lg border-n-ruby-6 text-n-slate-12"
          >
            {{ r.key }}
          </span>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="imageDialogRef"
      width="xl"
      title="选择产品图"
      description="默认从「设计资料」里挑，也能换板块或直接传本地图片"
      :show-confirm-button="false"
    >
      <div class="flex flex-col gap-3">
        <div class="flex items-center gap-2">
          <SelectCard
            :model-value="activeDocSection"
            :options="docSectionOptions"
            trigger-class="w-36 h-9"
            @update:model-value="onSwitchDocSection"
          />
          <Input
            v-model="docImageQuery"
            placeholder="搜文档名或图片文件名"
            class="flex-1"
            @keyup.enter="loadDocImages"
          />
          <Button
            label="搜索"
            variant="outline"
            size="sm"
            @click="loadDocImages"
          />
          <Button
            label="传本地图片"
            variant="outline"
            size="sm"
            icon="i-lucide-upload"
            @click="pickLocalFile"
          />
        </div>
        <div
          v-if="docImagesLoading"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          加载中…
        </div>
        <div
          v-else-if="!docImages.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          这个板块里没找到图片。换个板块，或直接传本地图片。
        </div>
        <div
          v-else
          class="grid grid-cols-2 gap-3 overflow-y-auto sm:grid-cols-4 max-h-96"
        >
          <button
            v-for="img in docImages"
            :key="img.id"
            class="flex flex-col gap-1 p-2 text-left border rounded-lg border-n-weak hover:border-n-iris-9"
            @click="chooseDocImage(img)"
          >
            <img
              :src="img.url"
              class="object-contain w-full h-24 rounded bg-n-alpha-1"
            />
            <span class="text-xs truncate text-n-slate-12">
              {{ img.filename }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ img.doc_name }}
            </span>
          </button>
        </div>
      </div>
    </Dialog>

    <Dialog
      ref="createDialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      title="新建报价单"
      description="一条产品线一张表，各自独立走版本"
      confirm-button-label="创建并录入"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitCreate"
      @close="markPristine"
      @save="submitCreate"
    >
      <div class="flex flex-col gap-3">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">产品线</span>
          <Input v-model="newForm.product_line" />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">标题（导出 PDF 的抬头）</span>
          <Input v-model="newForm.title" />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">生效日期</span>
            <DatePicker v-model="newForm.effective_on" />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">币种</span>
            <SelectCard
              v-model="newForm.currency"
              :options="CURRENCIES"
              trigger-class="h-9"
            />
          </label>
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            列（建完还能在编辑里加减、改名、切文本/价格）
          </span>
          <div class="flex flex-wrap gap-2">
            <div
              v-for="(c, i) in newForm.columns"
              :key="`nc-${i}`"
              class="flex items-center gap-1"
            >
              <Input v-model="c.label" class="w-28" />
              <SelectCard
                v-model="c.type"
                :options="COLUMN_TYPES"
                trigger-class="w-20 h-9"
              />
            </div>
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
