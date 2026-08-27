<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import { useMesBomTemplatesStore } from 'dashboard/stores/mes/bomTemplates';
import MesBomAPI from 'dashboard/api/mes/boms';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import {
  exportNodeToJpg,
  exportDataToExcel,
  printNode,
} from 'dashboard/helper/mesExport';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useMesProductLine } from 'dashboard/composables/useMesProductLine';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();
const route = useRoute();
const rootStore = useStore();

// 外购成品不经过生产：直接跳采购单页，自动进「成品(外购)」建单模式。
const goProductPurchase = () =>
  router.push(
    accountScopedRoute('mes_purchase_orders_index', {}, { new: 'product' })
  );
const store = useMesBomsStore();
const tplStore = useMesBomTemplatesStore();
const { mesCan } = useMesRole();

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 按阶段预估天数（不含销售出库/物流）。
const LEAD_STAGES = [
  { key: 'purchasingDays', label: '采购原料' },
  { key: 'materialInboundDays', label: '原料入库' },
  { key: 'pickingDays', label: '生产领料' },
  { key: 'productionDays', label: '生产' },
  { key: 'fgInboundDays', label: '成品入库' },
];

const products = ref([]);
// 关联成品为选填：置顶「不关联成品」哨兵项，让用户可显式清除选择
// （ComboBox 仅支持再点选中项才清空，不够直观）。
const productOptions = computed(() => [
  { value: '', label: '不关联成品' },
  ...products.value.map(p => ({ value: String(p.id), label: p.name })),
]);

// —— 用料明细：物料从产品档案「金蝶式表格下拉」选择（MesProductPicker），
// 选中回填该行的编码/名称/规格/单位。 ——
const pickMaterial = (row, p) => {
  if (!p) return;
  row.productId = String(p.id);
  row.materialNo = p.sku || '';
  row.materialName = p.name || '';
  if (p.specification) row.specification = p.specification;
  if (p.unit) row.unit = p.unit;
};

// 订单归属业务员：只列真正的业务角色（可归属 CRM 订单）——业务员/部门负责人/
// 副管理员；排除 HR 与无 CRM 角色的普通成员。选填。
const SALES_CRM_ROLES = ['sales', 'manager', 'deputy_admin'];
const agents = useMapGetter('agents/getAgents');
const salesOwnerOptions = computed(() => [
  { value: '', label: '未指定业务员' },
  ...(agents.value || [])
    .filter(a => SALES_CRM_ROLES.includes(a.crm_role))
    .map(a => ({ value: String(a.id), label: a.name })),
]);

const dialogRef = ref(null);
const editingId = ref(null);
const editingStatus = ref(null); // 编辑时的原状态：已下发则只显示「保存」
const removedItemIds = ref([]);
const releasingId = ref(null);

// 只读查看：点行直接看完整明细，无需进编辑态（车间/采购等无编辑权者也能看）。
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = bom => {
  viewing.value = bom;
  viewDialogRef.value?.open();
};
const viewHeaderFields = computed(() => {
  const v = viewing.value || {};
  return [
    { label: '投单日期', value: v.submitDate },
    { label: '投单单号', value: v.docNo },
    { label: '数量', value: v.orderQty },
    { label: '客户 / 项目', value: v.customerName },
    { label: '型号', value: v.model },
    { label: '产成品代码', value: v.productCode },
    { label: '裸机颜色', value: v.bareColor },
    { label: '皮套颜色', value: v.caseColor },
  ];
});
const blankLeadDays = () =>
  Object.fromEntries(LEAD_STAGES.map(s => [s.key, '']));
// 用料分类：整机生产物料 vs 包装物料（整机到齐即可开产，包装未到不挡生产）。
const CATEGORY_OPTIONS = [
  { value: 'MACHINE', label: '整机生产物料' },
  { value: 'PACKAGING', label: '包装物料' },
];
const categoryLabel = c =>
  CATEGORY_OPTIONS.find(o => o.value === c)?.label || '整机生产物料';

// 导出（Excel / 图片）
const viewContentRef = ref(null);
const bomExportData = () => {
  const v = viewing.value || {};
  return {
    title: v.bomNo ? `BOM ${v.bomNo}` : 'BOM',
    fields: [
      { label: '负责人', value: v.ownerName },
      { label: '归属业务员', value: v.salesOwnerName },
      { label: '关联成品', value: v.productName || '不关联成品' },
      { label: '基准产量', value: `${v.baseQty ?? ''} ${v.unit ?? ''}` },
      { label: '状态', value: v.status === 'RELEASED' ? '已下发' : '草稿' },
      ...viewHeaderFields.value,
      { label: '整单备注', value: v.remark },
    ],
    itemColumns: [
      { label: '类别', key: 'category' },
      { label: '物料编码', key: 'materialNo' },
      { label: '物料名称', key: 'materialName' },
      { label: '规格型号', key: 'specification' },
      { label: '单位', key: 'unit' },
      { label: '用量', key: 'qty', align: 'right' },
      { label: '备注', key: 'remark' },
    ],
    items: (v.bomItems || []).map(it => ({
      ...it,
      category: categoryLabel(it.category),
    })),
  };
};
const exportBomExcel = () => {
  const d = bomExportData();
  exportDataToExcel(d, d.title);
};
const exportBomJpg = () =>
  exportNodeToJpg(viewContentRef.value, bomExportData().title);
const printBom = () => printNode(viewContentRef.value, bomExportData().title);

// 用料明细每行照生产任务单直接填。
const blankRow = () => ({
  productId: '',
  materialNo: '',
  materialName: '',
  specification: '',
  unit: '',
  qty: '',
  remark: '',
  category: 'MACHINE',
});
// 投单信息（照 PMC 纸质 BOM 抬头）：日期/单号/客户/型号/产成品代码/数量/颜色。
const blankHeader = () => ({
  submitDate: '',
  docNo: '',
  customerName: '',
  model: '',
  productCode: '',
  orderQty: '',
  bareColor: '',
  caseColor: '',
});
const { activeProductLine } = useMesProductLine();
// 商显工控 BOM 不需要客户/项目名称、裸机颜色、皮套颜色（平板电脑保留）。
const showTabletHeaderFields = computed(
  () => activeProductLine.value !== 'COMMERCIAL_DISPLAY'
);

const form = reactive({
  crmProductId: '',
  salesOwnerId: '', // 订单归属业务员
  baseQty: '1',
  unit: '台',
  remark: '', // 整单备注（区别于每行的备注）
  ...blankHeader(),
  ...blankLeadDays(),
  rows: [], // { id?, materialNo, materialName, specification, unit, qty, remark }
});

const totalLeadDays = computed(() =>
  LEAD_STAGES.reduce((sum, s) => sum + (Number(form[s.key]) || 0), 0)
);

const invalid = computed(
  () =>
    !form.productCode.trim() ||
    !form.rows.length ||
    form.rows.some(
      r => !r.materialNo.trim() || !r.materialName.trim() || !Number(r.qty)
    )
);

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [removed] = form.rows.splice(i, 1);
  if (removed?.id) removedItemIds.value.push(removed.id);
};

// 关联生产订单（选填，仅新建）：「保存并下发」时自动挂接到该订单（进 BOM_READY、
// 通知业务员二次确认）。列表取停在「销售订单确定」的待挂 BOM 订单。
const attachOrderId = ref('');
const attachableOrders = ref([]);
const attachOrderOptions = computed(() => [
  { value: '', label: '不关联（仅建 BOM，不挂到订单）' },
  ...attachableOrders.value.map(o => ({
    value: String(o.id),
    label: `${o.order_no} · ${o.product_name} × ${o.qty} · ${o.owner_name || ''}`,
  })),
]);
const loadAttachableOrders = async () => {
  try {
    const { data } = await MesProductionOrderAPI.get({
      stage: 'SALES_CONFIRMED',
      status: 'IN_PROGRESS',
    });
    attachableOrders.value = data.payload || [];
  } catch {
    attachableOrders.value = [];
  }
};

// —— 图片 / 附件 ——
// 新增文件选择即暂存为 blob（拿 signed_id），保存时随 payload 追加挂载（append，不覆盖）。
// 编辑态的既有附件单独展示，删除即时调 detach 接口。
const pendingImages = ref([]); // [{ name, signedId, previewUrl }]
const pendingFiles = ref([]);
const existingImages = ref([]); // 编辑态既有：[{ id, filename, url }]
const existingFiles = ref([]);
const staging = ref(false);
const pendingFor = kind => (kind === 'images' ? pendingImages : pendingFiles);
const pickAttachment = async (event, kind) => {
  const list = Array.from(event.target.files || []);
  event.target.value = '';
  if (!list.length) return;
  const isImage = kind === 'images';
  staging.value = true;
  try {
    const staged = await Promise.all(
      list.map(file => {
        const fd = new FormData();
        fd.append('file', file);
        return MesBomAPI.stageBlob(fd).then(({ data }) => ({
          name: data.filename,
          signedId: data.signed_id,
          previewUrl: isImage ? URL.createObjectURL(file) : '',
        }));
      })
    );
    pendingFor(kind).value.push(...staged);
  } catch (e) {
    useAlert(
      `上传失败：${e?.response?.data?.error || e?.message || '未知错误'}`
    );
  } finally {
    staging.value = false;
  }
};
const removePending = (kind, i) => pendingFor(kind).value.splice(i, 1);
// 编辑态删除既有附件：即时生效。
const removeExisting = async (kind, att) => {
  try {
    await MesBomAPI.detachFile(editingId.value, att.id, kind);
    const list = kind === 'images' ? existingImages : existingFiles;
    list.value = list.value.filter(f => f.id !== att.id);
  } catch {
    useAlert('删除附件失败');
  }
};
const resetAttachments = () => {
  pendingImages.value = [];
  pendingFiles.value = [];
  existingImages.value = [];
  existingFiles.value = [];
};

// preOrderId：从生产订单页「去建 BOM」带来的预关联订单（自动选中「关联生产订单」）。
const openCreate = async (preOrderId = '') => {
  editingId.value = null;
  editingStatus.value = null;
  removedItemIds.value = [];
  attachOrderId.value = '';
  resetAttachments();
  Object.assign(form, {
    crmProductId: '',
    salesOwnerId: '',
    baseQty: '1',
    unit: '台',
    remark: '',
    ...blankHeader(),
    ...blankLeadDays(),
    rows: [blankRow()],
  });
  await loadAttachableOrders();
  // 预关联订单须在可挂列表里（SALES_CONFIRMED 待挂 BOM）才回填。
  if (
    preOrderId &&
    attachableOrders.value.some(o => String(o.id) === String(preOrderId))
  ) {
    attachOrderId.value = String(preOrderId);
  }
  dialogRef.value?.open();
};
const openEdit = bom => {
  editingId.value = bom.id;
  editingStatus.value = bom.status;
  removedItemIds.value = [];
  resetAttachments();
  existingImages.value = [...(bom.images || [])];
  existingFiles.value = [...(bom.files || [])];
  Object.assign(form, {
    crmProductId: bom.crmProductId ? String(bom.crmProductId) : '',
    salesOwnerId: bom.salesOwnerId ? String(bom.salesOwnerId) : '',
    baseQty: String(bom.baseQty ?? '1'),
    unit: bom.unit || '',
    remark: bom.remark || '',
    submitDate: bom.submitDate || '',
    docNo: bom.docNo || '',
    customerName: bom.customerName || '',
    model: bom.model || '',
    productCode: bom.productCode || '',
    orderQty: bom.orderQty ?? '',
    bareColor: bom.bareColor || '',
    caseColor: bom.caseColor || '',
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, bom[s.key] ?? ''])),
    rows: (bom.bomItems || []).map(it => ({
      id: it.id,
      productId: '',
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      qty: String(it.qty ?? ''),
      remark: it.remark || '',
      category: it.category || 'MACHINE',
    })),
  });
  dialogRef.value?.open();
};

// targetStatus：'DRAFT' 存草稿 / 'RELEASED' 下发。
const submit = async targetStatus => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      materialNo: r.materialNo.trim(),
      materialName: r.materialName.trim(),
      specification: r.specification.trim(),
      unit: r.unit.trim(),
      qty: Number(r.qty),
      remark: r.remark.trim(),
      category: r.category || 'MACHINE',
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    crmProductId: form.crmProductId || null,
    salesOwnerId: form.salesOwnerId || null,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    remark: form.remark.trim() || null,
    submitDate: form.submitDate || null,
    docNo: form.docNo.trim() || null,
    customerName: form.customerName.trim() || null,
    model: form.model.trim() || null,
    productCode: form.productCode.trim() || null,
    orderQty: Number(form.orderQty) || null,
    bareColor: form.bareColor.trim() || null,
    caseColor: form.caseColor.trim() || null,
    status: targetStatus,
    productionOrderId: editingId.value
      ? undefined
      : attachOrderId.value || null,
    images: pendingImages.value.map(p => p.signedId),
    files: pendingFiles.value.map(p => p.signedId),
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    const attached =
      !editingId.value && attachOrderId.value && targetStatus === 'RELEASED';
    const verb = targetStatus === 'RELEASED' ? '已下发' : '已存草稿';
    let msg;
    if (attached) msg = `已下发 ${ok.bomNo} 并挂接到订单，待业务员确认`;
    else if (editingId.value) msg = `BOM ${verb}`;
    else msg = `${verb} ${ok.bomNo}`;
    useAlert(msg);
    dialogRef.value?.close();
  }
};

// 列表里把草稿一键下发。
const release = async bom => {
  releasingId.value = bom.id;
  try {
    await MesBomAPI.release(bom.id);
    await store.get();
    useAlert(`已下发 ${bom.bomNo}`);
  } catch {
    useAlert('下发失败');
  } finally {
    releasingId.value = null;
  }
};

// —— BOM 模版：把常用成品的十几二十行用料存成模版，建 BOM 时一键套用 ——
const templates = computed(() => tplStore.getRecords);
const tplFetching = computed(() => tplStore.getUIFlags.fetchingList);
const tplSaving = computed(() => tplStore.getUIFlags.creatingItem);
const templateDialogRef = ref(null);
const saveTplDialogRef = ref(null);
const templateName = ref('');
const confirmingDeleteId = ref(null);
const tplDeletingId = ref(null);

const openTemplates = () => {
  confirmingDeleteId.value = null;
  tplStore.get();
  templateDialogRef.value?.open();
};

// 套用模版：预填新建 BOM 表单（模版不含成品，仍需选成品再保存）。
const applyTemplate = t => {
  editingId.value = null;
  editingStatus.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    crmProductId: '',
    baseQty: String(t.baseQty ?? '1'),
    unit: t.unit || '台',
    remark: '',
    ...blankHeader(),
    ...Object.fromEntries(LEAD_STAGES.map(s => [s.key, t[s.key] ?? ''])),
    rows: (t.bomTemplateItems || []).map(it => ({
      productId: '',
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      qty: String(it.qty ?? ''),
      remark: it.remark || '',
      category: it.category || 'MACHINE',
    })),
  });
  if (!form.rows.length) form.rows.push(blankRow());
  templateDialogRef.value?.close();
  dialogRef.value?.open();
};

const removeTemplate = async t => {
  tplDeletingId.value = t.id;
  try {
    await tplStore.delete(t.id);
    useAlert('模版已删除');
  } catch {
    useAlert('删除失败');
  } finally {
    tplDeletingId.value = null;
    confirmingDeleteId.value = null;
  }
};

// 从当前 BOM 表单存为模版（用料明细 + 各阶段天数，不含成品）。
const openSaveTemplate = () => {
  if (invalid.value) return;
  templateName.value = form.crmProductId
    ? productOptions.value.find(p => p.value === form.crmProductId)?.label || ''
    : '';
  saveTplDialogRef.value?.open();
};
const saveTemplate = async () => {
  const name = templateName.value.trim();
  if (!name) return;
  const payload = {
    name,
    baseQty: Number(form.baseQty) || 1,
    unit: form.unit,
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomTemplateItemsAttributes: form.rows
      .filter(r => r.materialName.trim() && Number(r.qty))
      .map(r => ({
        materialNo: r.materialNo.trim(),
        materialName: r.materialName.trim(),
        specification: r.specification.trim(),
        unit: r.unit.trim(),
        qty: Number(r.qty),
        remark: r.remark.trim(),
      })),
  };
  const ok = await tplStore.create(payload);
  if (ok) {
    useAlert(`已存为模版「${ok.name}」`);
    saveTplDialogRef.value?.close();
  }
};

onMounted(async () => {
  store.get();
  if (!agents.value?.length) rootStore.dispatch('agents/get');
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/products`
    );
    products.value = data?.payload || data || [];
  } catch {
    products.value = [];
  }
  // 从生产订单页「去建 BOM」跳来：自动打开新建 BOM 并预关联该订单。
  if (route.query.new_for_order) {
    openCreate(route.query.new_for_order);
    router.replace({ query: {} });
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-6 sm:py-4"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">工程/PMC BOM</h1>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="mesCan('purchase')"
          label="新建成品采购单"
          variant="outline"
          color="slate"
          size="sm"
          @click="goProductPurchase"
        />
        <template v-if="mesCan('bom')">
          <Button
            label="BOM 模版"
            variant="outline"
            color="slate"
            size="sm"
            @click="openTemplates"
          />
          <Button
            label="新建 BOM"
            color="iris"
            size="sm"
            @click="openCreate()"
          />
        </template>
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_boms_index" />

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <!-- 手机端卡片列表 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="b in records"
            :key="`card-${b.id}`"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(b)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">{{
                b.bomNo
              }}</span>
              <span
                class="px-2 py-0.5 text-xs rounded-full shrink-0"
                :class="
                  b.status === 'RELEASED'
                    ? 'bg-n-teal-3 text-n-teal-12'
                    : 'bg-n-slate-4 text-n-slate-11'
                "
              >
                {{ b.status === 'RELEASED' ? '已下发' : '草稿' }}
              </span>
              <span class="flex-1" />
              <Button
                v-if="mesCan('bom') && b.status !== 'RELEASED'"
                label="下发"
                color="iris"
                size="sm"
                class="shrink-0"
                :is-loading="releasingId === b.id"
                @click.stop="release(b)"
              />
              <Button
                v-if="mesCan('bom')"
                label="编辑"
                variant="ghost"
                size="sm"
                class="shrink-0"
                @click.stop="openEdit(b)"
              />
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              型号 / 成品：{{ b.model || b.productName || '—' }}
            </div>
            <div
              v-if="b.productCode || b.customerName"
              class="text-xs text-n-slate-11"
            >
              {{ [b.productCode, b.customerName].filter(Boolean).join(' · ') }}
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>负责人：{{ b.ownerName || '—' }}</span>
              <span>业务员：{{ b.salesOwnerName || '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>基准产量：{{ b.baseQty }} {{ b.unit }}</span>
              <span>用料项：{{ (b.bomItems || []).length }} 项</span>
              <span>预估周期：{{ b.totalLeadDays || '—' }} 天</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有 BOM。
          </div>
        </div>

        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">BOM 号</th>
              <th class="px-3 py-3 font-medium">型号 / 成品</th>
              <th class="px-3 py-3 font-medium">负责人</th>
              <th class="px-3 py-3 font-medium">归属业务员</th>
              <th class="px-3 py-3 font-medium">基准产量</th>
              <th class="px-3 py-3 font-medium">用料项</th>
              <th class="px-3 py-3 font-medium">预估周期(天)</th>
              <th class="px-3 py-3 font-medium">状态</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="b in records" :key="b.id" class="border-b border-n-weak">
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ b.bomNo }}
              </td>
              <td class="px-3 py-3">
                <div class="text-n-slate-12">
                  {{ b.model || b.productName || '—' }}
                </div>
                <div
                  v-if="b.productCode || b.customerName"
                  class="text-xs text-n-slate-10"
                >
                  {{
                    [b.productCode, b.customerName].filter(Boolean).join(' · ')
                  }}
                </div>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.ownerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.salesOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.baseQty }} {{ b.unit }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ (b.bomItems || []).length }} 项
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.totalLeadDays || '—' }}
              </td>
              <td class="px-3 py-3">
                <span
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="
                    b.status === 'RELEASED'
                      ? 'bg-n-teal-3 text-n-teal-12'
                      : 'bg-n-slate-4 text-n-slate-11'
                  "
                >
                  {{ b.status === 'RELEASED' ? '已下发' : '草稿' }}
                </span>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="flex justify-end gap-1">
                  <Button
                    v-if="mesCan('bom') && b.status !== 'RELEASED'"
                    label="下发"
                    color="iris"
                    size="sm"
                    :is-loading="releasingId === b.id"
                    @click="release(b)"
                  />
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(b)"
                  />
                  <Button
                    v-if="mesCan('bom')"
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="openEdit(b)"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
                还没有 BOM。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <Dialog
      :dismissible="false"
      ref="dialogRef"
      width="5xl"
      overflow-y-auto
      :show-confirm-button="false"
      :show-cancel-button="false"
      :title="editingId ? '编辑 BOM' : '新建 BOM'"
      :is-loading="saving"
    >
      <div class="flex flex-col gap-4">
        <!-- 关联生产订单（仅新建）：下发即自动挂接、通知业务员确认 -->
        <div v-if="!editingId" class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">关联生产订单（选填）</label>
          <SelectCard
            v-model="attachOrderId"
            :options="attachOrderOptions"
            block
          />
          <p class="text-xs text-n-slate-10">
            选择后「保存并下发」将直接挂接到该订单并通知业务员二次确认；存草稿不挂接。
          </p>
        </div>
        <!-- 投单信息（照 PMC 纸质 BOM 抬头） -->
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          投单信息
        </div>
        <div class="grid grid-cols-3 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">投单日期</label>
            <Input v-model="form.submitDate" type="date" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">投单单号</label>
            <Input v-model="form.docNo" placeholder="如 WT20260605-01" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">数量</label>
            <Input v-model="form.orderQty" type="number" placeholder="800" />
          </div>
          <div
            v-if="showTabletHeaderFields"
            class="flex flex-col col-span-3 gap-1"
          >
            <label class="text-xs text-n-slate-11">客户 / 项目名称</label>
            <Input
              v-model="form.customerName"
              placeholder="如 某业务员美国客户定制"
            />
          </div>
          <div class="flex flex-col col-span-2 gap-1">
            <label class="text-xs text-n-slate-11">型号</label>
            <Input
              v-model="form.model"
              placeholder="如 K13plus 10.1寸P30版/客户定制"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11"
              >产成品代码 <span class="text-n-ruby-11">*</span></label
            >
            <Input v-model="form.productCode" placeholder="如 P.01.842" />
          </div>
          <div v-if="showTabletHeaderFields" class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">裸机颜色</label>
            <Input v-model="form.bareColor" placeholder="如 橙色800" />
          </div>
          <div v-if="showTabletHeaderFields" class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">皮套颜色</label>
            <Input v-model="form.caseColor" placeholder="如 粉色400、蓝色400" />
          </div>
        </div>

        <div class="grid grid-cols-3 gap-4 pt-2 border-t border-n-weak">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >关联成品（选填，用于统计）</label
            >
            <ComboBox
              v-model="form.crmProductId"
              :options="productOptions"
              placeholder="选择成品"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >订单归属业务员（选填）</label
            >
            <ComboBox
              v-model="form.salesOwnerId"
              :options="salesOwnerOptions"
              placeholder="选择业务员"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12"
              >基准产量 / 单位</label
            >
            <div class="flex gap-2">
              <Input v-model="form.baseQty" type="number" class="w-20" />
              <Input v-model="form.unit" placeholder="台" />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <span class="text-heading-3 text-n-slate-12">各阶段预估天数</span>
            <span class="text-xs text-n-slate-11">
              预估周期合计：<span class="font-medium text-n-slate-12">{{
                totalLeadDays
              }}</span>
              天
            </span>
          </div>
          <div class="grid grid-cols-5 gap-2">
            <div
              v-for="s in LEAD_STAGES"
              :key="s.key"
              class="flex flex-col gap-1"
            >
              <label class="text-xs text-n-slate-11">{{ s.label }}</label>
              <Input v-model="form[s.key]" type="number" placeholder="天" />
            </div>
          </div>
        </div>

        <div
          class="flex items-center justify-between pt-2 border-t border-n-weak"
        >
          <span class="text-heading-3 text-n-slate-12">
            用料明细 <span class="text-n-ruby-11">*</span>
            <span class="ml-2 text-xs font-normal text-n-slate-10">
              整机生产物料到齐即可开产；包装物料未到不挡生产（生产领料只领整机料）
            </span>
          </span>
          <Button label="+ 加一行" variant="ghost" size="sm" @click="addRow" />
        </div>

        <div class="flex flex-col gap-2">
          <div class="grid grid-cols-12 gap-2 px-1 text-xs text-n-slate-11">
            <span class="col-span-2">类别</span>
            <span class="col-span-2"
              >物料编码 <span class="text-n-ruby-11">*</span></span
            >
            <span class="col-span-2"
              >物料名称 <span class="text-n-ruby-11">*</span></span
            >
            <span class="col-span-2">规格型号</span>
            <span class="col-span-1">单位</span>
            <span class="col-span-1"
              >用量 <span class="text-n-ruby-11">*</span></span
            >
            <span class="col-span-1">备注</span>
            <span class="col-span-1" />
          </div>
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="grid items-center grid-cols-12 gap-2"
          >
            <div class="col-span-2">
              <SelectCard
                v-model="row.category"
                :options="CATEGORY_OPTIONS"
                block
              />
            </div>
            <MesProductPicker
              :model-value="row.productId"
              :account-id="accountId"
              :display-text="
                row.materialNo
                  ? `${row.materialNo}${row.materialName ? ` · ${row.materialName}` : ''}`
                  : ''
              "
              placeholder="选物料"
              trigger-class="col-span-2"
              @select="p => pickMaterial(row, p)"
            />
            <Input
              :model-value="row.materialName"
              placeholder="选编码自动带出"
              disabled
              class="col-span-2"
            />
            <Input
              v-model="row.specification"
              placeholder="规格型号"
              class="col-span-2"
            />
            <Input v-model="row.unit" placeholder="台" class="col-span-1" />
            <Input
              v-model="row.qty"
              type="number"
              placeholder="用量"
              class="col-span-1"
            />
            <Input v-model="row.remark" placeholder="备注" class="col-span-1" />
            <button
              type="button"
              class="col-span-1 text-n-slate-10 hover:text-n-ruby-11"
              @click="removeRow(i)"
            >
              ✕
            </button>
          </div>
        </div>

        <div class="flex flex-col gap-1 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">整单备注</label>
          <TextArea
            v-model="form.remark"
            placeholder="整份 BOM 的说明，如工艺要求、替代料、注意事项等（不同于每行的备注）"
            :max-length="500"
            auto-height
          />
        </div>

        <!-- 结构图 / 样品图（选择即上传） -->
        <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">
            结构图 / 样品图
            <span v-if="staging" class="ml-1 text-xs text-n-amber-11">
              上传中…
            </span>
          </label>
          <div class="flex flex-wrap items-center gap-2">
            <div
              v-for="img in existingImages"
              :key="`ex-${img.id}`"
              class="relative w-20 h-20 group"
            >
              <a :href="img.url" target="_blank" rel="noopener noreferrer">
                <img
                  :src="img.url"
                  :alt="img.filename"
                  class="object-cover w-20 h-20 border rounded-lg border-n-weak"
                />
              </a>
              <button
                type="button"
                class="absolute items-center justify-center hidden w-5 h-5 text-xs text-white rounded-full top-1 right-1 bg-n-slate-12/70 group-hover:flex"
                @click="removeExisting('images', img)"
              >
                ✕
              </button>
            </div>
            <div
              v-for="(f, i) in pendingImages"
              :key="`pn-${i}`"
              class="relative w-20 h-20 group"
            >
              <img
                :src="f.previewUrl"
                class="object-cover w-20 h-20 border rounded-lg border-n-weak"
              />
              <button
                type="button"
                class="absolute items-center justify-center hidden w-5 h-5 text-xs text-white rounded-full top-1 right-1 bg-n-slate-12/70 group-hover:flex"
                @click="removePending('images', i)"
              >
                ✕
              </button>
            </div>
            <label
              class="flex items-center justify-center w-20 h-20 text-xs border border-dashed rounded-lg cursor-pointer border-n-weak text-n-slate-11 hover:text-n-slate-12"
            >
              + 图片
              <input
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                @change="e => pickAttachment(e, 'images')"
              />
            </label>
          </div>
        </div>

        <!-- 附件（工艺文档/图纸等） -->
        <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
          <label class="text-heading-3 text-n-slate-12">附件</label>
          <div class="flex flex-col gap-1">
            <div
              v-for="f in existingFiles"
              :key="`exf-${f.id}`"
              class="flex items-center justify-between text-xs"
            >
              <a
                :href="f.url"
                target="_blank"
                rel="noopener noreferrer"
                class="truncate text-n-iris-11 hover:underline"
              >
                {{ f.filename }}
              </a>
              <button
                type="button"
                class="ml-2 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeExisting('files', f)"
              >
                ✕
              </button>
            </div>
            <div
              v-for="(f, i) in pendingFiles"
              :key="`pnf-${i}`"
              class="flex items-center justify-between text-xs"
            >
              <span class="truncate text-n-slate-12">{{ f.name }}</span>
              <button
                type="button"
                class="ml-2 text-n-slate-10 hover:text-n-ruby-11"
                @click="removePending('files', i)"
              >
                ✕
              </button>
            </div>
            <label
              class="text-xs cursor-pointer text-n-iris-11 hover:underline w-max"
            >
              + 上传附件
              <input
                type="file"
                multiple
                class="hidden"
                @change="e => pickAttachment(e, 'files')"
              />
            </label>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="flex items-center justify-between gap-2">
          <Button
            label="存为模版"
            variant="outline"
            color="slate"
            :disabled="invalid"
            @click="openSaveTemplate"
          />
          <div class="flex justify-end gap-2">
            <Button
              label="取消"
              variant="ghost"
              color="slate"
              @click="dialogRef?.close()"
            />
            <!-- 已下发的编辑：只保留「保存修改」，保持已下发状态（非重新下发/非草稿） -->
            <Button
              v-if="editingId && editingStatus === 'RELEASED'"
              label="保存修改（保持下发）"
              color="iris"
              :is-loading="saving"
              :disabled="invalid"
              @click="submit('RELEASED')"
            />
            <template v-else>
              <Button
                label="存草稿"
                variant="outline"
                color="slate"
                :is-loading="saving"
                :disabled="invalid"
                @click="submit('DRAFT')"
              />
              <Button
                label="下发"
                color="iris"
                :is-loading="saving"
                :disabled="invalid"
                @click="submit('RELEASED')"
              />
            </template>
          </div>
        </div>
      </template>
    </Dialog>

    <!-- 只读查看：完整明细，无需进编辑态 -->
    <Dialog
      :dismissible="false"
      ref="viewDialogRef"
      width="5xl"
      overflow-y-auto
      :show-confirm-button="false"
      cancel-button-label="关闭"
      :title="viewing ? `BOM ${viewing.bomNo}` : 'BOM 明细'"
    >
      <div v-if="viewing" class="flex flex-col gap-4 text-sm">
        <div class="flex justify-end gap-2">
          <Button
            label="导出 Excel"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportBomExcel"
          />
          <Button
            label="导出图片"
            variant="outline"
            color="slate"
            size="sm"
            @click="exportBomJpg"
          />
          <Button
            label="打印"
            variant="outline"
            color="slate"
            size="sm"
            @click="printBom"
          />
        </div>
        <div
          ref="viewContentRef"
          class="flex flex-col gap-4 p-4 bg-white rounded-lg"
        >
          <div class="flex items-center gap-2">
            <span
              class="px-2 py-0.5 text-xs rounded-full"
              :class="
                viewing.status === 'RELEASED'
                  ? 'bg-n-teal-3 text-n-teal-12'
                  : 'bg-n-slate-4 text-n-slate-11'
              "
            >
              {{ viewing.status === 'RELEASED' ? '已下发' : '草稿' }}
            </span>
            <span class="text-n-slate-11">
              负责人：{{ viewing.ownerName || '—' }} · 归属业务员：{{
                viewing.salesOwnerName || '—'
              }}
              · 关联成品：{{ viewing.productName || '不关联成品' }} · 基准产量
              {{ viewing.baseQty }} {{ viewing.unit }}
            </span>
          </div>

          <div
            class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            投单信息
          </div>
          <div class="grid grid-cols-3 gap-x-4 gap-y-3">
            <div
              v-for="f in viewHeaderFields"
              :key="f.label"
              class="flex flex-col"
            >
              <span class="text-xs text-n-slate-10">{{ f.label }}</span>
              <span class="text-n-slate-12">{{ f.value || '—' }}</span>
            </div>
          </div>

          <div class="pt-2 border-t border-n-weak">
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              用料明细（{{ (viewing.bomItems || []).length }} 项）
            </div>
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-n-slate-11 border-b border-n-weak">
                  <th class="px-2 py-2 font-medium">类别</th>
                  <th class="px-2 py-2 font-medium">物料编码</th>
                  <th class="px-2 py-2 font-medium">物料名称</th>
                  <th class="px-2 py-2 font-medium">规格型号</th>
                  <th class="px-2 py-2 font-medium">单位</th>
                  <th class="px-2 py-2 font-medium text-right">用量</th>
                  <th class="px-2 py-2 font-medium">备注</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(it, i) in viewing.bomItems"
                  :key="i"
                  class="border-b border-n-weak"
                >
                  <td class="px-2 py-2">
                    <span
                      class="px-2 py-0.5 text-xs rounded-full"
                      :class="
                        it.category === 'PACKAGING'
                          ? 'bg-n-amber-3 text-n-amber-12'
                          : 'bg-n-iris-3 text-n-iris-12'
                      "
                    >
                      {{ categoryLabel(it.category) }}
                    </span>
                  </td>
                  <td class="px-2 py-2 text-n-slate-12">
                    {{ it.materialNo || '—' }}
                  </td>
                  <td class="px-2 py-2 text-n-slate-12">
                    {{ it.materialName }}
                  </td>
                  <td class="px-2 py-2 text-n-slate-11">
                    {{ it.specification || '—' }}
                  </td>
                  <td class="px-2 py-2 text-n-slate-11">
                    {{ it.unit || '—' }}
                  </td>
                  <td class="px-2 py-2 text-right text-n-slate-12">
                    {{ it.qty }}
                  </td>
                  <td class="px-2 py-2 text-n-slate-11">
                    {{ it.remark || '—' }}
                  </td>
                </tr>
                <tr v-if="!(viewing.bomItems || []).length">
                  <td colspan="7" class="px-2 py-6 text-center text-n-slate-11">
                    无用料明细
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="pt-2 border-t border-n-weak">
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              各阶段预估天数（合计 {{ viewing.totalLeadDays || 0 }} 天）
            </div>
            <div class="flex flex-wrap gap-x-6 gap-y-1 text-n-slate-11">
              <span v-for="s in LEAD_STAGES" :key="s.key">
                {{ s.label }}：<span class="text-n-slate-12">{{
                  viewing[s.key] || '—'
                }}</span>
              </span>
            </div>
          </div>

          <div v-if="viewing.remark" class="pt-2 border-t border-n-weak">
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              整单备注
            </div>
            <p class="whitespace-pre-wrap text-n-slate-12">
              {{ viewing.remark }}
            </p>
          </div>

          <div
            v-if="(viewing.images || []).length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-2 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              结构图 / 样品图
            </div>
            <div class="flex flex-wrap gap-2">
              <a
                v-for="img in viewing.images"
                :key="img.id"
                :href="img.url"
                target="_blank"
                rel="noopener noreferrer"
              >
                <img
                  :src="img.url"
                  :alt="img.filename"
                  class="object-cover w-20 h-20 border rounded-lg border-n-weak"
                />
              </a>
            </div>
          </div>

          <div
            v-if="(viewing.files || []).length"
            class="pt-2 border-t border-n-weak"
          >
            <div
              class="mb-1 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              附件
            </div>
            <ul class="flex flex-col gap-1">
              <li v-for="f in viewing.files" :key="f.id">
                <a
                  :href="f.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-n-iris-11 hover:underline"
                >
                  {{ f.filename }}
                </a>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- BOM 模版管理：套用 / 删除 -->
    <Dialog
      :dismissible="false"
      ref="templateDialogRef"
      width="2xl"
      overflow-y-auto
      :show-confirm-button="false"
      :show-cancel-button="false"
      title="BOM 模版"
    >
      <div class="flex flex-col gap-2">
        <p class="text-xs text-n-slate-11">
          套用模版会把用料明细与各阶段天数带入新建
          BOM，你只需再选成品即可保存。想新增模版？在新建/编辑 BOM
          时点「存为模版」。
        </p>
        <div v-if="tplFetching" class="py-8 text-center text-n-slate-11">
          加载中…
        </div>
        <div
          v-else-if="!templates.length"
          class="py-8 text-center text-n-slate-11"
        >
          还没有模版。
        </div>
        <div
          v-for="t in templates"
          v-else
          :key="t.id"
          class="flex items-center justify-between gap-3 px-3 py-2 border rounded-lg border-n-weak"
        >
          <div class="flex flex-col min-w-0">
            <span class="font-medium truncate text-n-slate-12">{{
              t.name
            }}</span>
            <span class="text-xs text-n-slate-11">
              {{ (t.bomTemplateItems || []).length }} 项用料 · 基准
              {{ t.baseQty }} {{ t.unit
              }}<template v-if="t.productLine"> · {{ t.productLine }}</template>
            </span>
          </div>
          <div class="flex items-center flex-shrink-0 gap-1">
            <template v-if="confirmingDeleteId === t.id">
              <Button
                label="确认删除"
                color="ruby"
                size="sm"
                :is-loading="tplDeletingId === t.id"
                @click="removeTemplate(t)"
              />
              <Button
                label="取消"
                variant="ghost"
                color="slate"
                size="sm"
                @click="confirmingDeleteId = null"
              />
            </template>
            <template v-else>
              <Button
                label="套用"
                color="iris"
                size="sm"
                @click="applyTemplate(t)"
              />
              <Button
                label="删除"
                variant="ghost"
                color="slate"
                size="sm"
                @click="confirmingDeleteId = t.id"
              />
            </template>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 存为模版：命名 -->
    <Dialog
      :dismissible="false"
      ref="saveTplDialogRef"
      width="sm"
      title="存为模版"
      confirm-button-label="保存模版"
      confirm-button-color="iris"
      :is-loading="tplSaving"
      :disable-confirm-button="!templateName.trim()"
      @confirm="saveTemplate"
    >
      <div class="flex flex-col gap-1">
        <label class="text-heading-3 text-n-slate-12">模版名称</label>
        <Input
          v-model="templateName"
          placeholder="如：55寸商显标准BOM"
          @keyup.enter="saveTemplate"
        />
        <span class="text-xs text-n-slate-11"
          >将保存当前
          {{ form.rows.length }} 行用料与各阶段天数（不含成品）。</span
        >
      </div>
    </Dialog>
  </div>
</template>
