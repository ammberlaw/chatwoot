<script setup>
/* global axios */
import { ref, computed, reactive, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesBomsStore } from 'dashboard/stores/mes/boms';
import { useMesBomTemplatesStore } from 'dashboard/stores/mes/bomTemplates';
import MesBomAPI from 'dashboard/api/mes/boms';

import Button from 'dashboard/components-next/button/Button.vue';
import { exportNodeToJpg, exportDataToExcel } from 'dashboard/helper/mesExport';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { accountId, accountScopedRoute } = useAccount();
const router = useRouter();
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

// 用料明细每行照生产任务单直接填。
const blankRow = () => ({
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

const openCreate = () => {
  editingId.value = null;
  editingStatus.value = null;
  removedItemIds.value = [];
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
  dialogRef.value?.open();
};
const openEdit = bom => {
  editingId.value = bom.id;
  editingStatus.value = bom.status;
  removedItemIds.value = [];
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
    ...Object.fromEntries(
      LEAD_STAGES.map(s => [s.key, Number(form[s.key]) || null])
    ),
    bomItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    const verb = targetStatus === 'RELEASED' ? '已下发' : '已存草稿';
    useAlert(editingId.value ? `BOM ${verb}` : `${verb} ${ok.bomNo}`);
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
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">工程/PMC BOM</h1>
      <div class="flex items-center gap-2">
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
          <Button label="新建 BOM" color="iris" size="sm" @click="openCreate" />
        </template>
      </div>
    </div>

    <MesBoardOwnerBar board-key="mes_boms_index" />

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
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
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ b.bomNo }}</td>
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
            <td class="px-3 py-3 text-n-slate-11">{{ b.ownerName || '—' }}</td>
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
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :show-confirm-button="false"
      :show-cancel-button="false"
      :title="editingId ? '编辑 BOM' : '新建 BOM'"
      :is-loading="saving"
    >
      <div class="flex flex-col gap-4">
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
          <div class="flex flex-col col-span-3 gap-1">
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
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">裸机颜色</label>
            <Input v-model="form.bareColor" placeholder="如 橙色800" />
          </div>
          <div class="flex flex-col gap-1">
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
            <select
              v-model="row.category"
              class="col-span-2 px-2 py-2 text-sm border rounded-lg outline-none border-n-weak bg-n-alpha-black1 text-n-slate-12"
            >
              <option
                v-for="c in CATEGORY_OPTIONS"
                :key="c.value"
                :value="c.value"
              >
                {{ c.label }}
              </option>
            </select>
            <Input
              v-model="row.materialNo"
              placeholder="P.03.201"
              class="col-span-2"
            />
            <Input
              v-model="row.materialName"
              placeholder="P30主板"
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
      ref="viewDialogRef"
      width="3xl"
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
        </div>
      </div>
    </Dialog>

    <!-- BOM 模版管理：套用 / 删除 -->
    <Dialog
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
