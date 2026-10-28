<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { useMesDocOwner } from 'dashboard/composables/useMesDocOwner';
import { useMesPurchaseRequisitionsStore } from 'dashboard/stores/mes/purchaseRequisitions';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesMaterialAPI from 'dashboard/api/mes/materials';
import MesPurchaseRequisitionAPI from 'dashboard/api/mes/purchaseRequisitions';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { orderSearchText } from 'dashboard/routes/dashboard/mes/orderSearchText';
import MesStatusPill from 'dashboard/components-next/mes/MesStatusPill.vue';

const ITEMS_PER_PAGE = 15;
const { accountId } = useAccount();
const { mesCan } = useMesRole();
const router = useRouter();
const store = useMesPurchaseRequisitionsStore();
const suppliersStore = useMesSuppliersStore();

const canManage = computed(() => mesCan('bom')); // 工程/PMC 提请购
const canConvert = computed(() => mesCan('purchase')); // 采购转采购单

const records = computed(() => store.getRecords);
const totalCount = computed(() => store.getMeta.count || 0);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

const PURPOSE_LABELS = {
  ORDER: '按单采购',
  STOCK: '备库存',
  ADHOC: '临时需求',
};
const STATUS_LABELS = {
  DRAFT: '草稿',
  OPEN: '待采购',
  PARTIAL_ORDERED: '部分已转',
  ORDERED: '已转采购',
  CANCELLED: '已作废',
};
const purposeOptions = Object.entries(PURPOSE_LABELS).map(([value, label]) => ({
  value,
  label,
}));
const statusFilterOptions = [
  { value: '', label: '全部状态' },
  ...Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label })),
];

// —— 筛选 + 分页 ——
const filterStatus = ref('');
const filterPurpose = ref('');
const search = ref('');
const currentPage = ref(1);

const load = () => {
  store.get({
    page: currentPage.value,
    per_page: ITEMS_PER_PAGE,
    status: filterStatus.value || undefined,
    purpose: filterPurpose.value || undefined,
    q: search.value.trim() || undefined,
  });
};
watch(currentPage, load);
watch([filterStatus, filterPurpose], () => {
  if (currentPage.value !== 1) currentPage.value = 1;
  else load();
});
let searchTimer = null;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    if (currentPage.value !== 1) currentPage.value = 1;
    else load();
  }, 300);
});

// —— 选项数据 ——
const productionOrders = ref([]);
const productionOrderOptions = computed(() =>
  productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
    searchText: orderSearchText(p),
  }))
);
const supplierOptions = computed(() => [
  { value: '', label: '（不指定供应商）' },
  ...(suppliersStore.getRecords || []).map(s => ({
    value: String(s.id),
    label: s.name,
  })),
]);
// 物料档案（编码唯一）：服务端按编码/名称搜索，选中才带出——不允许自定义输入。
const materialsList = ref([]);
const mergeMaterials = list => {
  const known = new Set(materialsList.value.map(m => String(m.id)));
  list.forEach(m => {
    if (!known.has(String(m.id))) {
      materialsList.value.push(m);
      known.add(String(m.id));
    }
  });
};
const loadMaterials = async (q = '') => {
  try {
    const { data } = await MesMaterialAPI.get(q ? { q } : {});
    mergeMaterials(data.payload || []);
  } catch {
    // 搜索失败不阻塞录入
  }
};
const onMaterialSearch = (line, term) => {
  line.codeSearch = term || '';
  if (line.codeSearch.trim()) loadMaterials(line.codeSearch.trim());
};
// 下拉选项按物料编码展示；已选项兜底保显示。无「新编码」项＝只能选档案已有编码。
const materialOptionsFor = line => {
  const raw = (line.codeSearch || '').trim();
  const term = raw.toLowerCase();
  let list = materialsList.value;
  if (term) {
    list = list.filter(
      m =>
        (m.material_no || '').toLowerCase().includes(term) ||
        (m.name || '').includes(raw)
    );
  }
  const opts = list.slice(0, 50).map(m => ({
    value: String(m.id),
    label: `${m.material_no || '(无编码)'}｜${m.name}（${m.unit || ''}）`,
  }));
  if (
    line.mesMaterialId &&
    !opts.some(o => o.value === String(line.mesMaterialId))
  ) {
    opts.unshift({
      value: String(line.mesMaterialId),
      label: `${line.materialNo || ''}｜${line.materialName || ''}`,
    });
  }
  return opts;
};
const selectMaterial = (line, v) => {
  line.mesMaterialId = v || '';
  const hit = materialsList.value.find(m => String(m.id) === String(v));
  if (!hit) return;
  line.materialName = hit.name || '';
  line.materialNo = hit.material_no || '';
  line.specification = hit.specification || '';
  line.unit = hit.unit || '';
  if (!line.mesSupplierId && hit.default_supplier_id) {
    line.mesSupplierId = String(hit.default_supplier_id);
  }
};

const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];

// —— 新建/编辑 ——
const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
const blankLine = () => ({
  id: undefined,
  itemType: 'MATERIAL',
  mesMaterialId: '',
  crmProductId: '',
  mesSupplierId: '',
  materialNo: '',
  materialName: '',
  specification: '',
  unit: '',
  requiredQty: '1',
  suggestedQty: '1',
  remark: '',
  codeSearch: '',
});
const form = reactive({
  purpose: 'ORDER',
  productionOrderId: '',
  expectedDate: '',
  remark: '',
  lines: [],
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

const lineIncomplete = l =>
  !Number(l.suggestedQty) ||
  (l.itemType === 'PRODUCT' ? !l.crmProductId : !l.mesMaterialId);
const invalid = computed(
  () =>
    !form.lines.length ||
    form.lines.some(lineIncomplete) ||
    (form.purpose === 'ORDER' && !form.productionOrderId)
);

const addLine = () => form.lines.push(blankLine());
const removeLine = i => {
  const [l] = form.lines.splice(i, 1);
  if (l?.id) removedItemIds.value.push(l.id);
};

const onProductPicked = (line, p) => {
  line.crmProductId = String(p.id);
  line.materialName = p.name || '';
  line.materialNo = p.sku || '';
  line.specification = p.specification || '';
  line.unit = p.unit || '';
};

// BOM 算料：按关联生产订单展开需求，覆盖当前明细行（need 与 suggest 初值相同）。
const explode = async (category = '') => {
  if (!form.productionOrderId) {
    useAlert('请先选销售订单');
    return;
  }
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/requirement`,
      {
        params: {
          production_order_id: form.productionOrderId,
          category: category || undefined,
        },
      }
    );
    const reqs = data?.payload || [];
    if (!reqs.length) {
      useAlert(category ? '该类别无用料' : '该销售订单未挂生产任务单或无用料');
      return;
    }
    // BOM 算料出的物料并入下拉数据源，编码下拉才显示得出已选项。
    mergeMaterials(
      reqs
        .filter(r => r.mes_material_id)
        .map(r => ({
          id: r.mes_material_id,
          material_no: r.material_no,
          name: r.material_name,
          specification: r.specification,
          unit: r.unit,
        }))
    );
    form.lines.forEach(l => l.id && removedItemIds.value.push(l.id));
    form.lines = reqs.map(r => ({
      ...blankLine(),
      itemType: r.crm_product_id ? 'PRODUCT' : 'MATERIAL',
      mesMaterialId: r.mes_material_id ? String(r.mes_material_id) : '',
      crmProductId: r.crm_product_id ? String(r.crm_product_id) : '',
      mesSupplierId: r.mes_supplier_id ? String(r.mes_supplier_id) : '',
      materialNo: r.material_no || '',
      materialName: r.material_name || '',
      specification: r.specification || '',
      unit: r.unit || '',
      requiredQty: String(r.qty),
      suggestedQty: String(r.qty),
    }));
  } catch {
    useAlert('算料失败');
  }
};

const resetForm = () => {
  editingId.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    purpose: 'ORDER',
    productionOrderId: '',
    expectedDate: '',
    remark: '',
    lines: [blankLine()],
  });
};
const openCreate = () => {
  resetForm();
  markPristine();
  dialogRef.value?.open();
};
const openEdit = req => {
  editingId.value = req.id;
  removedItemIds.value = [];
  // 已选物料并入下拉数据源，编辑时编码下拉才显示得出。
  mergeMaterials(
    (req.requisitionItems || [])
      .filter(it => it.mesMaterialId)
      .map(it => ({
        id: it.mesMaterialId,
        material_no: it.materialNo,
        name: it.materialName,
        specification: it.specification,
        unit: it.unit,
      }))
  );
  Object.assign(form, {
    purpose: req.purpose || 'ORDER',
    productionOrderId: req.productionOrderId
      ? String(req.productionOrderId)
      : '',
    expectedDate: req.expectedDate ? req.expectedDate.slice(0, 10) : '',
    remark: req.remark || '',
    lines: (req.requisitionItems || []).map(it => ({
      id: it.id,
      itemType: it.itemType || 'MATERIAL',
      mesMaterialId: it.mesMaterialId ? String(it.mesMaterialId) : '',
      crmProductId: it.crmProductId ? String(it.crmProductId) : '',
      mesSupplierId: it.mesSupplierId ? String(it.mesSupplierId) : '',
      materialNo: it.materialNo || '',
      materialName: it.materialName || '',
      specification: it.specification || '',
      unit: it.unit || '',
      requiredQty: String(it.requiredQty ?? ''),
      suggestedQty: String(it.suggestedQty ?? ''),
      remark: it.remark || '',
      codeSearch: '',
    })),
  });
  markPristine();
  dialogRef.value?.open();
};

const buildPayload = () => ({
  purpose: form.purpose,
  productionOrderId: form.purpose === 'ORDER' ? form.productionOrderId : null,
  expectedDate: form.expectedDate || null,
  remark: form.remark.trim() || null,
  requisitionItemsAttributes: [
    ...form.lines.map(l => ({
      id: l.id || undefined,
      itemType: l.itemType,
      mesMaterialId: l.itemType === 'PRODUCT' ? null : Number(l.mesMaterialId),
      crmProductId: l.itemType === 'PRODUCT' ? Number(l.crmProductId) : null,
      mesSupplierId: l.mesSupplierId ? Number(l.mesSupplierId) : null,
      materialNo: l.materialNo || null,
      materialName: l.materialName || null,
      specification: l.specification || null,
      unit: l.unit || null,
      requiredQty: Number(l.requiredQty) || 0,
      suggestedQty: Number(l.suggestedQty) || 0,
      remark: l.remark || null,
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ],
});

// status='DRAFT' 存草稿 / 'OPEN' 提交（提交后采购可见可转）。
const submit = async status => {
  if (invalid.value) return;
  const payload = { ...buildPayload(), status };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    let msg;
    if (status === 'OPEN')
      msg = editingId.value ? '已提交，采购可转采购单' : `已提交 ${ok.reqNo}`;
    else msg = editingId.value ? '已保存草稿' : `已存草稿 ${ok.reqNo}`;
    useAlert(msg);
    dialogRef.value?.close();
  }
};

const submitRow = async req => {
  await MesPurchaseRequisitionAPI.submit(req.id);
  useAlert('已提交，采购可转采购单');
  load();
};
const cancelRow = async req => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定作废「${req.reqNo}」？`)) return;
  await MesPurchaseRequisitionAPI.cancel(req.id);
  useAlert('已作废');
  load();
};
const removeRow = async req => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除「${req.reqNo}」？`)) return;
  if (await store.delete(req.id)) useAlert('已删除');
};

// —— 转采购单（拆批 + 改量）——
const convertDialogRef = ref(null);
const convertReq = ref(null);
const convertForm = reactive({
  expectedDate: '',
  deliveryDate: '',
  remark: '',
  lines: [],
});
const { isDirty: isConvertDirty, markPristine: markConvertPristine } =
  useDirtyGuard(() => convertForm);
const converting = ref(false);
const openConvert = req => {
  convertReq.value = req;
  Object.assign(convertForm, {
    expectedDate: '',
    deliveryDate: '',
    remark: '',
    lines: (req.requisitionItems || [])
      .filter(it => Number(it.remainingQty) > 0)
      .map(it => ({
        requisitionItemId: it.id,
        label: it.materialName || it.materialNo || '物料',
        specification: it.specification || '',
        unit: it.unit || '',
        requiredQty: it.requiredQty,
        suggestedQty: it.suggestedQty,
        orderedQty: it.orderedQty,
        remaining: it.remainingQty,
        qty: String(it.remainingQty),
        mesSupplierId: it.mesSupplierId ? String(it.mesSupplierId) : '',
      })),
  });
  markConvertPristine();
  convertDialogRef.value?.open();
};
const convertInvalid = computed(
  () => !convertForm.lines.some(l => Number(l.qty) > 0)
);
const doConvert = async () => {
  if (convertInvalid.value || !convertReq.value) return;
  converting.value = true;
  try {
    const payload = {
      lines: convertForm.lines
        .filter(l => Number(l.qty) > 0)
        .map(l => ({
          requisition_item_id: l.requisitionItemId,
          qty: Number(l.qty),
          mes_supplier_id: l.mesSupplierId || null,
        })),
      expected_date: convertForm.expectedDate || null,
      delivery_date: convertForm.deliveryDate || null,
      remark: convertForm.remark || null,
    };
    const { data } = await MesPurchaseRequisitionAPI.convert(
      convertReq.value.id,
      payload
    );
    useAlert(`已生成采购单 ${data.payload.po_no}`);
    convertDialogRef.value?.close();
    load();
    router.push({
      name: 'mes_purchase_orders_index',
      query: { q: data.payload.po_no },
    });
  } catch {
    useAlert('转采购单失败');
  } finally {
    converting.value = false;
  }
};

// —— 查看 ——
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = req => {
  viewing.value = req;
  viewDialogRef.value?.open();
};
const viewHeaderFields = computed(() => {
  const v = viewing.value || {};
  return [
    { label: '申请单号', value: v.reqNo },
    { label: '用途', value: PURPOSE_LABELS[v.purpose] || v.purpose },
    { label: '状态', value: STATUS_LABELS[v.status] || v.status },
    { label: '销售订单', value: v.productionOrderNo || '—' },
    { label: '产品', value: v.productName || '—' },
    { label: '制单人', value: v.ownerName || '—' },
    { label: '期望到料', value: v.expectedDate || '—' },
    { label: '已转采购单', value: `${v.poCount || 0} 张` },
  ];
});

const { isMyDoc } = useMesDocOwner();
// 谁制单谁改：非制单人连编辑/删除按钮都不露（后端同样拦）。
const canEditRow = req =>
  canManage.value && isMyDoc(req) && ['DRAFT', 'OPEN'].includes(req.status);

onMounted(() => {
  load();
  suppliersStore.get({ per_page: 500 });
  loadMaterials();
  axios
    .get(`/api/v1/accounts/${accountId.value}/mes/production_orders`, {
      // 下拉要能选到所有在产订单:不传 per_page 后端只给最新 15 条(RESULTS_PER_PAGE),
      // 早一点的单子在下拉里根本找不到。封顶 500。
      params: { per_page: 500 },
    })
    .then(({ data }) => {
      productionOrders.value = data?.payload || [];
    })
    .catch(() => {
      productionOrders.value = [];
    });
});
// 导出：一张申请单几项料就几行（申请单级字段每行重复写）——Excel 里没有卡片，
// 不铺平就没法按物料筛选/透视，而采购正是拿这张表去凑量下单的。
// ⚠️ 全量：列表一页 15 张，导出重新向后端分页要完。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const reqs = await fetchAllRows(
      params => MesPurchaseRequisitionAPI.get(params),
      {
        status: filterStatus.value || undefined,
        purpose: filterPurpose.value || undefined,
        q: search.value.trim() || undefined,
      }
    );
    // 接口直拉的是未驼峰化的原始 payload，字段用下划线。
    const rows = reqs.flatMap(req =>
      (req.requisition_items || []).map(item => ({
        req_no: req.req_no,
        status_label: STATUS_LABELS[req.status] || req.status,
        purpose: req.purpose,
        production_order_no: req.production_order_no,
        product_name: req.product_name,
        owner_name: req.owner_name,
        expected_date: req.expected_date,
        material_no: item.material_no,
        material_name: item.material_name,
        specification: item.specification,
        unit: item.unit,
        required_qty: item.required_qty,
        suggested_qty: item.suggested_qty,
        ordered_qty: item.ordered_qty,
        supplier_name: item.supplier_name,
      }))
    );
    exportRowsToExcel(
      {
        title: '采购申请单',
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '关键字', value: search.value.trim() || '（无）' },
          { label: '申请单数', value: reqs.length },
          { label: '明细行数', value: rows.length },
        ],
        columns: [
          { label: '申请单号', key: 'req_no' },
          { label: '状态', key: 'status_label' },
          { label: '用途', key: 'purpose' },
          { label: '关联销售订单', key: 'production_order_no' },
          { label: '成品', key: 'product_name' },
          { label: '申请人', key: 'owner_name' },
          { label: '期望到货', key: 'expected_date' },
          { label: '物料编码', key: 'material_no' },
          { label: '物料/成品', key: 'material_name' },
          { label: '规格', key: 'specification' },
          { label: '单位', key: 'unit' },
          { label: '需求量', key: 'required_qty', num: true },
          { label: '建议采购量', key: 'suggested_qty', num: true },
          { label: '已转', key: 'ordered_qty', num: true },
          { label: '建议供应商', key: 'supplier_name' },
        ],
        rows,
      },
      `采购申请单_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        采购申请单
      </h1>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，不挂管理权限 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          @click="exportList"
        />
        <Button
          v-if="canManage"
          label="新建申请单"
          icon="i-lucide-plus"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div
      class="flex-1 px-4 pt-1 pb-6 overflow-y-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <!-- 筛选栏：三控件统一 h-9/text-sm 对齐，紧凑内联 -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <SelectCard
          :model-value="filterStatus"
          :options="statusFilterOptions"
          @update:model-value="v => (filterStatus = v)"
        />
        <SelectCard
          :model-value="filterPurpose"
          :options="[{ value: '', label: '全部用途' }, ...purposeOptions]"
          @update:model-value="v => (filterPurpose = v)"
        />
        <input
          v-model="search"
          type="text"
          placeholder="搜索申请单号"
          class="w-52 h-9 px-3 mb-0 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
        />
        <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
      </div>

      <div
        v-if="isFetching && !records.length"
        class="py-16 text-sm text-center text-n-slate-10"
      >
        加载中…
      </div>
      <div
        v-else-if="!records.length"
        class="py-16 text-sm text-center text-n-slate-10"
      >
        还没有采购申请单。
      </div>

      <div v-else class="flex flex-col gap-2">
        <div
          v-for="(req, ri) in records"
          :key="req.id"
          class="flex flex-col gap-2 p-3 border shadow-sm rounded-xl border-white/70 bg-n-solid-1/60"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs tabular-nums text-n-slate-10">{{
              ri + 1
            }}</span>
            <span class="font-semibold text-n-slate-12">{{ req.reqNo }}</span>
            <span
              class="px-2 py-0.5 text-xs rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ PURPOSE_LABELS[req.purpose] || req.purpose }}
            </span>
            <MesStatusPill :label="STATUS_LABELS[req.status] || req.status" />
            <span
              v-if="req.poCount"
              class="px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
            >
              已转 {{ req.poCount }} 张采购单
            </span>
            <span class="ml-auto text-xs text-n-slate-10">
              制单：{{ req.ownerName || '—' }}
            </span>
          </div>
          <div class="flex flex-wrap gap-4 text-xs text-n-slate-11">
            <span v-if="req.productionOrderNo">
              生产订单：{{ req.productionOrderNo }} · {{ req.productName }}
            </span>
            <span>明细：{{ (req.requisitionItems || []).length }} 项</span>
            <span v-if="req.expectedDate">
              期望到料：{{ req.expectedDate }}
            </span>
          </div>
          <div class="flex flex-wrap items-center gap-2 pt-1">
            <Button
              label="查看"
              variant="outline"
              color="slate"
              size="xs"
              @click="openView(req)"
            />
            <Button
              v-if="canEditRow(req)"
              label="编辑"
              variant="outline"
              color="slate"
              size="xs"
              @click="openEdit(req)"
            />
            <Button
              v-if="canManage && req.status === 'DRAFT'"
              label="提交"
              color="iris"
              size="xs"
              @click="submitRow(req)"
            />
            <Button
              v-if="
                canConvert && ['OPEN', 'PARTIAL_ORDERED'].includes(req.status)
              "
              label="转采购单"
              color="amber"
              size="xs"
              icon="i-lucide-shopping-cart"
              @click="openConvert(req)"
            />
            <Button
              v-if="canManage && req.status !== 'CANCELLED'"
              label="作废"
              variant="ghost"
              color="ruby"
              size="xs"
              @click="cancelRow(req)"
            />
            <Button
              v-if="canManage && isMyDoc(req) && req.status === 'DRAFT'"
              label="删除"
              variant="ghost"
              color="ruby"
              size="xs"
              @click="removeRow(req)"
            />
          </div>
        </div>

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          class="mt-3 !bg-transparent before:!hidden"
          @update:current-page="currentPage = $event"
        />
      </div>
    </div>

    <!-- 新建/编辑 -->
    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="5xl"
      overflow-y-auto
      :title="editingId ? '编辑采购申请单' : '新建采购申请单'"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :dirty="isDirty"
      dirty-save-label="存草稿"
      :disable-confirm-button="invalid"
      @close="markPristine"
      @save="submit('DRAFT')"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">用途</label>
            <SelectCard
              :model-value="form.purpose"
              :options="purposeOptions"
              block
              @update:model-value="v => (form.purpose = v)"
            />
          </div>
          <div v-if="form.purpose === 'ORDER'" class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              生产订单
            </label>
            <ComboBox
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              placeholder="选择销售订单…"
              search-placeholder="搜 MO 号 / 产品 / 销售订单 / 客户"
              empty-state="没有匹配的生产订单"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              期望到料日期
            </label>
            <DatePicker v-model="form.expectedDate" block />
          </div>
        </div>

        <div
          v-if="form.purpose === 'ORDER'"
          class="flex flex-wrap items-center gap-2"
        >
          <span class="text-sm text-n-slate-11">按生产任务单算料：</span>
          <Button
            label="全部用料"
            variant="outline"
            color="slate"
            size="xs"
            @click="explode('')"
          />
          <Button
            label="仅主料"
            variant="outline"
            color="slate"
            size="xs"
            @click="explode('MACHINE')"
          />
          <Button
            label="仅辅料"
            variant="outline"
            color="slate"
            size="xs"
            @click="explode('PACKAGING')"
          />
        </div>

        <!-- 明细行 -->
        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <label class="text-sm font-medium text-n-slate-12">
              申请明细
            </label>
            <Button
              label="加一行"
              icon="i-lucide-plus"
              variant="outline"
              color="slate"
              size="xs"
              @click="addLine"
            />
          </div>
          <div
            v-for="(line, i) in form.lines"
            :key="i"
            class="grid items-end grid-cols-1 gap-2 p-2 border rounded-lg sm:grid-cols-12 border-n-weak"
          >
            <div class="sm:col-span-12 -mb-1">
              <span class="text-xs font-medium tabular-nums text-n-slate-10">
                序号 {{ i + 1 }}
              </span>
            </div>
            <div class="sm:col-span-2">
              <label class="text-heading-3 text-n-slate-12">类型</label>
              <SelectCard
                :model-value="line.itemType"
                :options="ITEM_TYPE_OPTIONS"
                block
                @update:model-value="v => (line.itemType = v)"
              />
            </div>
            <div class="sm:col-span-3">
              <label class="text-heading-3 text-n-slate-12">
                {{ line.itemType === 'PRODUCT' ? '成品' : '物料' }}
              </label>
              <MesProductPicker
                v-if="line.itemType === 'PRODUCT'"
                :account-id="accountId"
                :model-value="line.crmProductId"
                :display-text="line.materialName"
                placeholder="选择外购成品"
                @update:model-value="v => (line.crmProductId = v)"
                @select="p => onProductPicked(line, p)"
              />
              <ComboBox
                v-else
                :model-value="line.mesMaterialId"
                :options="materialOptionsFor(line)"
                search-placeholder="输入物料编码或名称搜索"
                @search="term => onMaterialSearch(line, term)"
                @update:model-value="v => selectMaterial(line, v)"
              />
            </div>
            <div class="sm:col-span-2">
              <label class="text-heading-3 text-n-slate-12">需求量</label>
              <Input
                v-model="line.requiredQty"
                type="number"
                class="reset-base"
              />
            </div>
            <div class="sm:col-span-2">
              <label class="text-heading-3 text-n-slate-12">建议采购量</label>
              <Input
                v-model="line.suggestedQty"
                type="number"
                class="reset-base"
              />
            </div>
            <div class="sm:col-span-2">
              <label class="text-heading-3 text-n-slate-12">建议供应商</label>
              <SelectCard
                :model-value="line.mesSupplierId"
                :options="supplierOptions"
                block
                @update:model-value="v => (line.mesSupplierId = v)"
              />
            </div>
            <div class="flex justify-end sm:col-span-1">
              <Button
                icon="i-lucide-trash-2"
                variant="ghost"
                color="ruby"
                size="xs"
                @click="removeLine(i)"
              />
            </div>
            <div class="sm:col-span-12">
              <Input
                v-model="line.remark"
                placeholder="备注"
                class="reset-base"
              />
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">整单备注</label>
          <Input v-model="form.remark" placeholder="选填" class="reset-base" />
        </div>
      </div>

      <template #footer>
        <div class="flex justify-end gap-2">
          <Button
            label="取消"
            variant="ghost"
            color="slate"
            @click="dialogRef?.close()"
          />
          <Button
            label="存草稿"
            variant="outline"
            color="slate"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit('DRAFT')"
          />
          <Button
            label="提交"
            color="iris"
            :is-loading="saving"
            :disabled="invalid"
            @click="submit('OPEN')"
          />
        </div>
      </template>
    </Dialog>

    <!-- 转采购单（拆批 + 改量）-->
    <Dialog
      ref="convertDialogRef"
      :dismissible="false"
      width="4xl"
      overflow-y-auto
      title="转采购单"
      description="一张申请可分批多次转采购"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :dirty="isConvertDirty"
      dirty-save-label="生成采购单"
      :disable-confirm-button="convertInvalid"
      @close="markConvertPristine"
      @save="doConvert"
    >
      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">回复交期</label>
            <DatePicker v-model="convertForm.expectedDate" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">交货时间</label>
            <DatePicker v-model="convertForm.deliveryDate" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">采购单备注</label>
            <Input v-model="convertForm.remark" class="reset-base" />
          </div>
        </div>

        <div
          v-if="!convertForm.lines.length"
          class="py-8 text-sm text-center text-n-slate-10"
        >
          该申请单已全部转采购，无剩余可转明细。
        </div>
        <div
          v-for="(line, ci) in convertForm.lines"
          :key="line.requisitionItemId"
          class="grid items-end grid-cols-1 gap-2 p-2 border rounded-lg sm:grid-cols-12 border-n-weak"
        >
          <div class="sm:col-span-4">
            <div class="text-sm font-medium text-n-slate-12">
              <span class="tabular-nums text-n-slate-10">{{ ci + 1 }}.</span>
              {{ line.label }}
            </div>
            <div class="text-xs text-n-slate-10">
              {{ line.specification }}
            </div>
          </div>
          <div class="text-xs sm:col-span-3 text-n-slate-11">
            需求 {{ line.requiredQty }} · 建议 {{ line.suggestedQty }} · 已转
            {{ line.orderedQty }} · 剩余 {{ line.remaining }}
          </div>
          <div class="sm:col-span-2">
            <label class="text-heading-3 text-n-slate-12">本批采购量</label>
            <Input v-model="line.qty" type="number" class="reset-base" />
          </div>
          <div class="sm:col-span-3">
            <label class="text-heading-3 text-n-slate-12">供应商</label>
            <SelectCard
              :model-value="line.mesSupplierId"
              :options="supplierOptions"
              block
              @update:model-value="v => (line.mesSupplierId = v)"
            />
          </div>
        </div>
      </div>

      <template #footer>
        <div class="flex justify-end gap-2">
          <Button
            label="取消"
            variant="ghost"
            color="slate"
            @click="convertDialogRef?.close()"
          />
          <Button
            label="生成采购单"
            color="amber"
            :is-loading="converting"
            :disabled="convertInvalid"
            @click="doConvert"
          />
        </div>
      </template>
    </Dialog>

    <!-- 查看 -->
    <Dialog
      ref="viewDialogRef"
      :dismissible="false"
      width="4xl"
      overflow-y-auto
      :title="viewing ? `采购申请单 ${viewing.reqNo}` : '采购申请单'"
      :show-confirm-button="false"
      cancel-button-label="关闭"
    >
      <div v-if="viewing" class="flex flex-col gap-3">
        <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <div
            v-for="f in viewHeaderFields"
            :key="f.label"
            class="flex flex-col"
          >
            <span class="text-xs text-n-slate-10">{{ f.label }}</span>
            <span class="text-sm text-n-slate-12">{{ f.value }}</span>
          </div>
        </div>
        <div class="text-heading-2 text-n-slate-12">
          申请明细（{{ (viewing.requisitionItems || []).length }} 项）
        </div>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-xs text-left text-n-slate-10">
              <th class="py-1 w-8 whitespace-nowrap">#</th>
              <th class="py-1 whitespace-nowrap">物料/成品</th>
              <th class="py-1 whitespace-nowrap">规格</th>
              <th class="py-1 text-right whitespace-nowrap">需求量</th>
              <th class="py-1 text-right whitespace-nowrap">建议采购量</th>
              <th class="py-1 text-right whitespace-nowrap">已转</th>
              <th class="py-1 whitespace-nowrap">单位</th>
              <th class="py-1 whitespace-nowrap">建议供应商</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(it, vi) in viewing.requisitionItems"
              :key="it.id"
              class="border-t border-n-weak"
            >
              <td class="py-1 tabular-nums text-n-slate-10">{{ vi + 1 }}</td>
              <td class="py-1">{{ it.materialName || it.materialNo }}</td>
              <td class="py-1 text-n-slate-11">
                {{ it.specification || '—' }}
              </td>
              <td class="py-1 text-right">{{ it.requiredQty }}</td>
              <td class="py-1 text-right">{{ it.suggestedQty }}</td>
              <td class="py-1 text-right">{{ it.orderedQty }}</td>
              <td class="py-1">{{ it.unit || '—' }}</td>
              <td class="py-1 text-n-slate-11">
                {{ it.supplierName || '—' }}
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="viewing.remark" class="pt-2 text-sm border-t border-n-weak">
          备注：{{ viewing.remark }}
        </div>
      </div>
    </Dialog>
  </div>
</template>
