<script setup>
/* global axios */
import { ref, computed, reactive, onMounted, nextTick, watch } from 'vue';
import { useRoute } from 'vue-router';
import html2canvas from 'html2canvas';
import { jsPDF as JsPDF } from 'jspdf';
import JSZip from 'jszip';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesPurchaseOrdersStore } from 'dashboard/stores/mes/purchaseOrders';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';
import MesPurchaseOrderAPI from 'dashboard/api/mes/purchaseOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import MesBoardOwnerBar from 'dashboard/components-next/mes/MesBoardOwnerBar.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MesProductPicker from 'dashboard/components-next/mes/MesProductPicker.vue';
import MesViewDialog from 'dashboard/components-next/mes/MesViewDialog.vue';
import MesReturnControls from 'dashboard/components-next/mes/MesReturnControls.vue';
import MesPoSupplierDoc from 'dashboard/components-next/mes/MesPoSupplierDoc.vue';

const { accountId } = useAccount();
const route = useRoute();
const store = useMesPurchaseOrdersStore();
const { mesCan } = useMesRole();
const suppliersStore = useMesSuppliersStore();
const currentUserId = useMapGetter('getCurrentUserID');

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(
  () => store.getUIFlags.creatingItem || store.getUIFlags.updatingItem
);

// 搜索：单号 / 供应商 / 归属人 / 生产订单 / 物料编码（后端跨字段 ILIKE）。
const search = ref('');
const totalCount = computed(() => store.getMeta?.count || 0);
const fetchList = () => store.get({ q: search.value.trim() || undefined });
let searchTimer = null;
watch(search, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchList, 300);
});

const day = d => (d ? new Date(d).toLocaleDateString() : '—');
// micros → ¥金额（两位小数），空值给「—」。采购模块内部可见价格，销售端不涉及。
const yuan = micros =>
  micros == null || micros === ''
    ? '—'
    : `¥${(micros / 1e6).toLocaleString('zh-CN', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`;

const STATUS_LABELS = {
  DRAFT: '草稿',
  SUBMITTED: '已下单',
  PARTIAL_RECEIVED: '部分到货',
  RECEIVED: '已到货',
  CANCELLED: '已取消',
};
const statusOptions = Object.entries(STATUS_LABELS).map(([value, label]) => ({
  value,
  label,
}));

// 审批状态（总经理一级）：与收货状态正交。
const APPROVAL_LABELS = {
  DRAFT: '草稿',
  PENDING_GM: '待总经理审批',
  APPROVED: '已通过',
  REJECTED: '已驳回',
};
const APPROVAL_COLORS = {
  DRAFT: 'text-n-slate-11',
  PENDING_GM: 'text-n-amber-11',
  APPROVED: 'text-n-teal-11',
  REJECTED: 'text-n-ruby-11',
};

// 提交审批：草稿/被驳回可提交（制单人操作）。
const submitForApproval = async po => {
  try {
    await MesPurchaseOrderAPI.submit(po.id);
    useAlert('已提交总经理审批');
    fetchList();
  } catch {
    useAlert('提交失败，请重试');
  }
};
// 总经理通过。
const approvePo = async po => {
  try {
    await MesPurchaseOrderAPI.approve(po.id);
    useAlert('已通过，库存已记在途');
    fetchList();
  } catch {
    useAlert('审批失败，请重试');
  }
};
// 总经理驳回（填原因）。
const rejectPo = async po => {
  // eslint-disable-next-line no-alert
  const reason = window.prompt('请填写驳回原因');
  if (reason === null) return;
  try {
    await MesPurchaseOrderAPI.reject(po.id, reason);
    useAlert('已驳回');
    fetchList();
  } catch {
    useAlert('驳回失败，请重试');
  }
};
// 我是本单当前审批人（总经理）吗？→ 显示通过/驳回。
const canApprove = po =>
  po.approvalStatus === 'PENDING_GM' &&
  po.currentApproverId === currentUserId.value;
// 我能提交本单审批吗？→ 制单人本人、草稿或被驳回。
const canSubmit = po =>
  mesCan('purchase') &&
  ['DRAFT', 'REJECTED'].includes(po.approvalStatus) &&
  po.ownerId === currentUserId.value;

// 按供应商拆单导出为 PDF：每供应商一份（抬头/税口径按各自 bill_entity），打包 zip 下载。
// 后端给分组数据 → 前端离屏渲染各供应商 PO 版式 → html2canvas 截图 → jsPDF 出 PDF → jszip 打包。
const exportDocs = ref([]); // 当前离屏渲染的供应商列表
const exportMeta = reactive({ poNo: '', date: '', deliveryDate: '' });
const docEls = ref([]); // 各供应商 PO DOM 元素
const exporting = ref(false);
const setDocEl = (el, i) => {
  docEls.value[i] = el;
};

const triggerDownload = (blob, filename) => {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
};

// 等元素内所有图片（logo/公章 base64）解码完成，避免 html2canvas 截到空白。
const waitForImages = async el => {
  const imgs = Array.from(el.querySelectorAll('img'));
  await Promise.all(
    imgs.map(img =>
      img.complete && img.naturalWidth
        ? Promise.resolve()
        : img.decode().catch(() => {})
    )
  );
};

// 单个供应商 DOM → 单份 PDF（按 A4 宽等比，超一页自动分页）。
const elementToPdfBlob = async el => {
  await waitForImages(el);
  const canvas = await html2canvas(el, {
    scale: 2,
    backgroundColor: '#ffffff',
    useCORS: true,
  });
  const img = canvas.toDataURL('image/jpeg', 0.92);
  const pdf = new JsPDF({ unit: 'pt', format: 'a4' });
  const pageW = pdf.internal.pageSize.getWidth();
  const pageH = pdf.internal.pageSize.getHeight();
  const imgH = (canvas.height * pageW) / canvas.width;
  let heightLeft = imgH;
  let position = 0;
  pdf.addImage(img, 'JPEG', 0, position, pageW, imgH);
  heightLeft -= pageH;
  while (heightLeft > 0) {
    position -= pageH;
    pdf.addPage();
    pdf.addImage(img, 'JPEG', 0, position, pageW, imgH);
    heightLeft -= pageH;
  }
  return pdf.output('blob');
};

const exportBySupplier = async po => {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/purchase_orders/${po.id}/export_data`
    );
    const payload = data.payload || {};
    const suppliers = payload.suppliers || [];
    if (!suppliers.length) {
      useAlert('该采购单没有可导出的明细');
      return;
    }
    exportMeta.poNo = payload.po_no || po.poNo;
    exportMeta.date = payload.date || '';
    exportMeta.deliveryDate = payload.delivery_date || '';
    docEls.value = [];
    exportDocs.value = suppliers;
    await nextTick();
    await new Promise(resolve => {
      setTimeout(resolve, 60);
    });
    const zip = new JSZip();
    const used = {};
    for (let i = 0; i < suppliers.length; i += 1) {
      const el = docEls.value[i];
      if (el) {
        // 顺序生成：html2canvas/jsPDF 逐份处理，避免并发抢渲染。
        // eslint-disable-next-line no-await-in-loop
        const blob = await elementToPdfBlob(el);
        let base = (suppliers[i].name || '供应商').replace(
          /[/\\:*?"<>|]/g,
          '_'
        );
        used[base] = (used[base] || 0) + 1;
        if (used[base] > 1) base = `${base}-${used[base]}`;
        zip.file(`${base}.pdf`, blob);
      }
    }
    const content = await zip.generateAsync({ type: 'blob' });
    triggerDownload(content, `采购单-${exportMeta.poNo}-按供应商.zip`);
  } catch {
    useAlert('导出失败，请重试');
  } finally {
    exportDocs.value = [];
    exporting.value = false;
  }
};

// 只读查看
const viewDialogRef = ref(null);
const viewing = ref(null);
const openView = po => {
  viewing.value = po;
  viewDialogRef.value?.open();
};
const viewFields = computed(() => {
  const p = viewing.value || {};
  return [
    { label: '采购单号', value: p.poNo },
    { label: '供应商', value: (p.supplierNames || []).join('、') || '—' },
    { label: '生产订单', value: p.productionOrderNo },
    { label: '归属人', value: p.productionOrderOwnerName },
    { label: '收货状态', value: STATUS_LABELS[p.status] || p.status },
    { label: '采购总额', value: yuan(p.totalAmountMicros) },
    {
      label: '审批状态',
      value: APPROVAL_LABELS[p.approvalStatus] || '—',
    },
    { label: '审批总经理', value: p.gmName || '—' },
    { label: '审批意见', value: p.gmComment || '—' },
    { label: '回复交期', value: day(p.expectedDate) },
    { label: '交货时间', value: day(p.deliveryDate) },
    {
      label: '异常',
      value: p.hasException ? p.exceptionNote || '有异常' : '无',
    },
    { label: '制单人', value: p.ownerName },
    { label: '备注', value: p.remark },
  ];
});
const VIEW_ITEM_COLS = [
  { label: '类型', key: 'typeLabel' },
  { label: '编码', key: 'code' },
  { label: '名称', key: 'name' },
  { label: '规格型号', key: 'spec' },
  { label: '供应商', key: 'supplierName' },
  { label: '采购量', key: 'qty', align: 'right' },
  { label: '已到料', key: 'receivedQty', align: 'right' },
  { label: '单位', key: 'unit' },
  { label: '单价', key: 'rate', align: 'right' },
  { label: '税率', key: 'taxRate', align: 'right' },
  { label: '金额', key: 'amount', align: 'right' },
  { label: '实际到料时间', key: 'arrival' },
  { label: '备注', key: 'remark' },
];
const viewItems = computed(() =>
  (viewing.value?.purchaseItems || []).map(it => ({
    typeLabel: it.itemType === 'PRODUCT' ? '成品(外购)' : '物料',
    code: it.productSku || it.materialNo || '—',
    name: it.productName || it.materialName || '—',
    spec: it.specification || '—',
    supplierName: it.supplierName || '—',
    qty: it.qty,
    receivedQty: it.receivedQty,
    unit: it.unit,
    rate: it.rateMicros
      ? `${yuan(it.rateMicros)}${it.priceTaxIncluded ? '(含税)' : ''}`
      : '—',
    taxRate: it.supplierTaxRate ? `${it.supplierTaxRate}%` : '—',
    amount: yuan(it.amountMicros),
    arrival: day(it.arrivalDate),
    remark: it.remark,
  }))
);

const productionOrders = ref([]);
const productionOrderOptions = computed(() => [
  { value: '', label: '不关联生产订单' },
  ...productionOrders.value.map(p => ({
    value: String(p.id),
    label: `${p.order_no} · ${p.product_name}`,
  })),
]);
const supplierOptions = computed(() =>
  (suppliersStore.getRecords || []).map(s => ({
    value: String(s.id),
    label: s.name,
  }))
);
// 采购行类型：物料（生产用料）/ 成品（外购贸易品，不经过生产部）。
const ITEM_TYPE_OPTIONS = [
  { value: 'MATERIAL', label: '物料' },
  { value: 'PRODUCT', label: '成品(外购)' },
];

// CRM 成品选项：服务端搜索（成品可能较多），并保留已选项的标签。
const productOptions = ref([]);
const mergeProductOptions = list => {
  const seen = new Set(productOptions.value.map(o => o.value));
  list.forEach(o => {
    if (!seen.has(o.value)) {
      productOptions.value.push(o);
      seen.add(o.value);
    }
  });
};
const productUnit = id =>
  productOptions.value.find(o => o.value === String(id))?.unit || '';
const productLabel = id =>
  productOptions.value.find(o => o.value === String(id))?.label || '';
// 规格型号取自所选产品档案（统一物料档案 = 产品档案）。
const productSpec = id =>
  productOptions.value.find(o => o.value === String(id))?.specification || '';
// 对应物料实时库存（产品搜索/算料时带回的跨仓合计），选料即显示。
const productOnHand = id => {
  const o = productOptions.value.find(x => x.value === String(id));
  return o && o.onHand != null ? o.onHand : null;
};
// MesProductPicker 选中：把该产品并入 productOptions，保证行内显示文本、规格、单位、实时库存都可查。
const onProductPicked = p =>
  mergeProductOptions([
    {
      value: String(p.id),
      label: `${p.name}${p.sku ? `（${p.sku}）` : ''}${
        p.specification ? ` · ${p.specification}` : ''
      }`,
      unit: p.unit || '',
      specification: p.specification || '',
      onHand: p.on_hand != null ? Number(p.on_hand) : null,
    },
  ]);

const dialogRef = ref(null);
const editingId = ref(null);
const removedItemIds = ref([]);
// 明细行：物料/成品统一从产品档案选（crmProductId）；供应商、含税/未税、实际到料时间都在行上。
const blankRow = () => ({
  itemType: 'MATERIAL',
  crmProductId: '',
  mesSupplierId: '',
  arrivalDate: '',
  qty: '1',
  rate: '',
  priceTaxIncluded: false,
  suggestedQty: null, // 工程建议采购量（BOM 算料带出，只读参考）
  remark: '',
});
const form = reactive({
  productionOrderId: '',
  status: 'DRAFT',
  expectedDate: '',
  deliveryDate: '',
  hasException: false,
  exceptionNote: '',
  rows: [],
});

const rowIncomplete = r => !Number(r.qty) || !r.crmProductId;
// 供应商税率（%）：用于含税/未税提示。
const supplierTaxRate = id =>
  (suppliersStore.getRecords || []).find(s => String(s.id) === String(id))
    ?.taxRate || 0;
const invalid = computed(
  () => !form.rows.length || form.rows.some(rowIncomplete)
);
// 采购单合计（元）= Σ 数量 × 单价，实时预览（保存后后端按 amount_micros 汇总总额）。
const orderTotal = computed(() =>
  form.rows.reduce((s, r) => s + Number(r.qty || 0) * Number(r.rate || 0), 0)
);

const addRow = () => form.rows.push(blankRow());
const removeRow = i => {
  const [r] = form.rows.splice(i, 1);
  if (r?.id) removedItemIds.value.push(r.id);
};

// 从关联的生产订单 BOM 算料，覆盖当前明细行。
// category='' 全部 / 'MACHINE' 只主料(整机料) / 'PACKAGING' 只辅料(包装料)——两个采购员分料建单。
const explode = async (category = '') => {
  if (!form.productionOrderId) {
    useAlert('请先选生产订单');
    return;
  }
  try {
    const { data } = await MesPurchaseOrderAPI.requirement(
      form.productionOrderId,
      category
    );
    const reqs = data?.payload || [];
    if (!reqs.length) {
      useAlert(
        category ? '该类别（主料/辅料）无用料' : '该生产订单未挂 BOM 或无用料'
      );
      return;
    }
    form.rows.forEach(r => r.id && removedItemIds.value.push(r.id));
    // 料号能对上产品档案 SKU 的自动带出产品；对不上的留空让采购手动选（并把料号信息放备注提示）。
    mergeProductOptions(
      reqs
        .filter(r => r.crm_product_id)
        .map(r => ({
          value: String(r.crm_product_id),
          label: `${r.material_name || ''}${r.material_no ? `（${r.material_no}）` : ''}${
            r.specification ? ` · ${r.specification}` : ''
          }`,
          unit: r.unit || '',
          specification: r.specification || '',
          onHand: r.on_hand != null ? Number(r.on_hand) : null,
        }))
    );
    form.rows = reqs.map(r => ({
      ...blankRow(),
      crmProductId: r.crm_product_id ? String(r.crm_product_id) : '',
      mesSupplierId: r.mes_supplier_id ? String(r.mes_supplier_id) : '',
      qty: String(r.qty),
      suggestedQty:
        r.suggested_purchase_qty != null
          ? Number(r.suggested_purchase_qty)
          : null,
      // 料号对不上产品档案时把料号/名称/规格留备注，方便采购手动补选。
      remark: r.crm_product_id
        ? ''
        : [r.material_no, r.material_name, r.specification]
            .filter(Boolean)
            .join(' '),
    }));
  } catch {
    useAlert('算料失败');
  }
};

const resetForm = () => {
  editingId.value = null;
  removedItemIds.value = [];
  Object.assign(form, {
    productionOrderId: '',
    status: 'DRAFT',
    expectedDate: '',
    deliveryDate: '',
    hasException: false,
    exceptionNote: '',
    rows: [blankRow()],
  });
};

const openCreate = () => {
  resetForm();
  dialogRef.value?.open();
};
// 从工程/PMC BOM 的「新建成品采购单」跳来：首行直接切成外购成品。
const openProductCreate = () => {
  resetForm();
  form.rows[0].itemType = 'PRODUCT';
  dialogRef.value?.open();
};
const openEdit = po => {
  editingId.value = po.id;
  removedItemIds.value = [];
  Object.assign(form, {
    productionOrderId: po.productionOrderId ? String(po.productionOrderId) : '',
    status: po.status,
    expectedDate: po.expectedDate ? po.expectedDate.slice(0, 10) : '',
    deliveryDate: po.deliveryDate ? po.deliveryDate.slice(0, 10) : '',
    hasException: !!po.hasException,
    exceptionNote: po.exceptionNote || '',
    rows: (po.purchaseItems || []).map(it => ({
      id: it.id,
      itemType: it.itemType || 'MATERIAL',
      crmProductId: it.crmProductId ? String(it.crmProductId) : '',
      mesSupplierId: it.mesSupplierId ? String(it.mesSupplierId) : '',
      arrivalDate: it.arrivalDate ? it.arrivalDate.slice(0, 10) : '',
      qty: String(it.qty),
      rate: it.rateMicros ? String(it.rateMicros / 1e6) : '',
      priceTaxIncluded: !!it.priceTaxIncluded,
      remark: it.remark || '',
    })),
  });
  // 回填已选产品的标签/规格，保证下拉能显示名称
  mergeProductOptions(
    (po.purchaseItems || [])
      .filter(it => it.crmProductId)
      .map(it => ({
        value: String(it.crmProductId),
        label: `${it.productName || ''}${it.productSku ? `（${it.productSku}）` : ''}`,
        unit: it.unit || '',
        specification: it.specification || '',
      }))
  );
  dialogRef.value?.open();
};

const submit = async () => {
  if (invalid.value) return;
  const itemsAttributes = [
    ...form.rows.map(r => ({
      id: r.id || undefined,
      itemType: r.itemType,
      mesMaterialId: null,
      crmProductId: Number(r.crmProductId),
      mesSupplierId: r.mesSupplierId ? Number(r.mesSupplierId) : null,
      arrivalDate: r.arrivalDate || null,
      unit: productUnit(r.crmProductId) || undefined,
      qty: Number(r.qty),
      rateMicros: r.rate ? Math.round(Number(r.rate) * 1e6) : null,
      priceTaxIncluded: r.priceTaxIncluded,
      remark: r.remark || '',
    })),
    ...removedItemIds.value.map(id => ({ id, _destroy: true })),
  ];
  const payload = {
    productionOrderId: form.productionOrderId || null,
    status: form.status,
    expectedDate: form.expectedDate || null,
    deliveryDate: form.deliveryDate || null,
    hasException: form.hasException,
    exceptionNote: form.exceptionNote,
    purchaseItemsAttributes: itemsAttributes,
  };
  const ok = editingId.value
    ? await store.update({ id: editingId.value, ...payload })
    : await store.create(payload);
  if (ok) {
    useAlert(editingId.value ? '采购单已更新' : `已新建 ${ok.poNo}`);
    dialogRef.value?.close();
  }
};

onMounted(async () => {
  fetchList();
  // 供应商下拉需全量，默认分页只出第一页会漏选。
  suppliersStore.get({ per_page: 500 });
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/mes/production_orders`
    );
    productionOrders.value = data?.payload || [];
  } catch {
    productionOrders.value = [];
  }
  if (route.query.new === 'product' && mesCan('purchase')) openProductCreate();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">采购单</h1>
      <Button
        v-if="mesCan('purchase')"
        label="新建采购单"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <MesBoardOwnerBar board-key="mes_purchase_orders_index" />

    <!-- 搜索：单号/供应商/归属人/生产订单/物料编码 -->
    <div class="flex items-center gap-2 px-4 pt-1 pb-2 sm:px-6">
      <input
        v-model="search"
        type="text"
        placeholder="搜索单号 / 供应商 / 归属人 / 生产订单 / 物料编码"
        class="w-80 h-9 px-3 mb-0 text-sm rounded-lg reset-base outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 hover:outline-n-brand focus:outline-n-brand"
      />
      <span class="text-sm text-n-slate-11">共 {{ totalCount }} 条</span>
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="p in records"
            :key="p.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openView(p)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ p.poNo }}
              </span>
              <span
                v-if="p.hasException"
                class="text-xs shrink-0 text-n-ruby-11"
                title="采购异常"
              >
                ⚠
              </span>
              <span class="text-xs shrink-0 text-n-slate-11">
                {{ STATUS_LABELS[p.status] }}
              </span>
              <span
                class="text-xs shrink-0"
                :class="APPROVAL_COLORS[p.approvalStatus]"
              >
                {{ APPROVAL_LABELS[p.approvalStatus] || '' }}
              </span>
              <span class="flex-1" />
              <div class="flex gap-1 shrink-0" @click.stop>
                <Button
                  v-if="canSubmit(p)"
                  label="提交审批"
                  color="iris"
                  size="sm"
                  @click="submitForApproval(p)"
                />
                <Button
                  v-if="canApprove(p)"
                  label="通过"
                  color="teal"
                  size="sm"
                  @click="approvePo(p)"
                />
                <Button
                  v-if="canApprove(p)"
                  label="驳回"
                  color="ruby"
                  variant="outline"
                  size="sm"
                  @click="rejectPo(p)"
                />
                <Button
                  v-if="mesCan('purchase')"
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="openEdit(p)"
                />
                <MesReturnControls
                  :record="p"
                  :store="store"
                  :can-manage="mesCan('purchase')"
                />
              </div>
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              供应商：{{ (p.supplierNames || []).join('、') || '—' }}
            </div>
            <div class="flex flex-wrap mt-1 gap-3 text-xs text-n-slate-11">
              <span>生产订单：{{ p.productionOrderNo || '—' }}</span>
              <span>归属人：{{ p.productionOrderOwnerName || '—' }}</span>
            </div>
            <div class="flex flex-wrap mt-1 gap-3 text-xs text-n-slate-11">
              <span>回复交期：{{ day(p.expectedDate) }}</span>
              <span>交货：{{ day(p.deliveryDate) }}</span>
              <span>总额：{{ yuan(p.totalAmountMicros) }}</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            还没有采购单。
          </div>
        </div>
        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium whitespace-nowrap">采购单号</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">供应商</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">生产订单</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">归属人</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">收货状态</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                总额
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">审批</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">回复交期</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">交货时间</th>
              <th class="px-3 py-3" />
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in records" :key="p.id" class="border-b border-n-weak">
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ p.poNo }}
                <span
                  v-if="p.hasException"
                  class="ml-1 text-xs text-n-ruby-11"
                  title="采购异常"
                >
                  ⚠
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ (p.supplierNames || []).join('、') || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ p.productionOrderNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ p.productionOrderOwnerName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ STATUS_LABELS[p.status] }}
              </td>
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ yuan(p.totalAmountMicros) }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <span :class="APPROVAL_COLORS[p.approvalStatus]">
                  {{ APPROVAL_LABELS[p.approvalStatus] || '—' }}
                </span>
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ day(p.expectedDate) }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ day(p.deliveryDate) }}
              </td>
              <td class="px-3 py-3 text-right whitespace-nowrap">
                <div class="flex justify-end gap-1">
                  <Button
                    label="查看"
                    variant="ghost"
                    size="sm"
                    @click="openView(p)"
                  />
                  <Button
                    v-if="canSubmit(p)"
                    label="提交审批"
                    color="iris"
                    size="sm"
                    @click="submitForApproval(p)"
                  />
                  <Button
                    v-if="canApprove(p)"
                    label="通过"
                    color="teal"
                    size="sm"
                    @click="approvePo(p)"
                  />
                  <Button
                    v-if="canApprove(p)"
                    label="驳回"
                    color="ruby"
                    variant="outline"
                    size="sm"
                    @click="rejectPo(p)"
                  />
                  <Button
                    v-if="mesCan('purchase')"
                    label="编辑"
                    variant="ghost"
                    size="sm"
                    @click="openEdit(p)"
                  />
                  <Button
                    :label="exporting ? '导出中…' : '按供应商导出'"
                    variant="ghost"
                    size="sm"
                    :disabled="exporting"
                    @click="exportBySupplier(p)"
                  />
                  <MesReturnControls
                    :record="p"
                    :store="store"
                    :can-manage="mesCan('purchase')"
                  />
                </div>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="11" class="px-3 py-10 text-center text-n-slate-11">
                还没有采购单。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="3xl"
      overflow-y-auto
      confirm-button-color="iris"
      :title="editingId ? '编辑采购单' : '新建采购单'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col items-stretch gap-2 sm:flex-row sm:items-end">
          <div class="flex flex-col flex-1 gap-1">
            <label class="text-heading-3 text-n-slate-12">关联生产订单</label>
            <SelectCard
              size="form"
              :model-value="form.productionOrderId"
              :options="productionOrderOptions"
              @update:model-value="v => (form.productionOrderId = v)"
            />
          </div>
          <div class="flex flex-wrap items-center gap-1">
            <Button
              label="算全部料"
              type="button"
              color="slate"
              size="sm"
              @click="explode('')"
            />
            <Button
              label="只算主料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('MACHINE')"
            />
            <Button
              label="只算辅料"
              type="button"
              variant="outline"
              color="slate"
              size="sm"
              @click="explode('PACKAGING')"
            />
          </div>
        </div>
        <p class="-mt-2 text-xs text-n-slate-10">
          一张生产订单可开多张采购单（如主料、辅料各一张，不同采购员各建各的）。
        </p>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">状态</label>
            <SelectCard
              size="form"
              :model-value="form.status"
              :options="statusOptions"
              @update:model-value="v => (form.status = v)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">回复采购时间</label>
            <DatePicker v-model="form.expectedDate" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">交货时间</label>
            <DatePicker v-model="form.deliveryDate" block />
            <span class="text-xs text-n-slate-10">
              导出合同"三、交货时间"用
            </span>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
            <input v-model="form.hasException" type="checkbox" />
            采购异常
          </label>
          <Input
            v-if="form.hasException"
            v-model="form.exceptionNote"
            placeholder="异常说明"
          />
        </div>

        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            采购明细 <span class="text-n-ruby-11">*</span>
          </span>
          <Button
            label="+ 加一行"
            type="button"
            variant="ghost"
            size="sm"
            @click="addRow"
          />
        </div>
        <div class="flex flex-col gap-2.5">
          <div
            v-for="(row, i) in form.rows"
            :key="i"
            class="flex flex-col gap-2.5 p-3 border rounded-lg border-n-weak"
          >
            <!-- 主控件行：类型 / 物料 / 供应商 / 数量 / 单价 / 删除 -->
            <div class="grid items-center grid-cols-1 gap-2 md:grid-cols-12">
              <div class="md:col-span-2">
                <SelectCard
                  size="form"
                  :model-value="row.itemType"
                  :options="ITEM_TYPE_OPTIONS"
                  @update:model-value="v => (row.itemType = v)"
                />
              </div>
              <div class="md:col-span-3">
                <MesProductPicker
                  :account-id="accountId"
                  :model-value="row.crmProductId"
                  :display-text="productLabel(row.crmProductId)"
                  placeholder="选择物料（产品档案·编码/名称/规格）"
                  @update:model-value="v => (row.crmProductId = v)"
                  @select="onProductPicked"
                />
              </div>
              <div class="md:col-span-2">
                <ComboBox
                  v-model="row.mesSupplierId"
                  :options="supplierOptions"
                  placeholder="选择供应商"
                />
              </div>
              <Input
                v-model="row.qty"
                type="number"
                placeholder="数量"
                class="md:col-span-2"
              />
              <Input
                v-model="row.rate"
                type="number"
                :placeholder="row.priceTaxIncluded ? '含税单价' : '未税单价'"
                class="md:col-span-2"
              />
              <button
                type="button"
                class="justify-self-end md:col-span-1 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeRow(i)"
              >
                ✕
              </button>
            </div>
            <!-- 次要控件行：含税 / 实际到料 / 备注 -->
            <div class="grid items-center grid-cols-1 gap-2 md:grid-cols-12">
              <label
                class="flex items-center gap-1.5 text-xs md:col-span-3 text-n-slate-11"
              >
                <input v-model="row.priceTaxIncluded" type="checkbox" />
                <span class="shrink-0">单价含税</span>
                <span
                  v-if="row.mesSupplierId && supplierTaxRate(row.mesSupplierId)"
                  class="text-n-slate-10"
                >
                  （税率{{ supplierTaxRate(row.mesSupplierId) }}%）
                </span>
              </label>
              <div class="flex items-center gap-2 md:col-span-4">
                <label class="text-xs shrink-0 text-n-slate-11">实际到料</label>
                <div class="flex-1">
                  <DatePicker v-model="row.arrivalDate" block />
                </div>
              </div>
              <Input
                v-model="row.remark"
                placeholder="备注"
                class="md:col-span-5"
              />
            </div>
            <!-- 只读信息：规格 · 实时库存 · 工程建议采购 -->
            <div
              class="flex flex-wrap gap-x-5 gap-y-1 pt-0.5 text-xs border-t border-n-weak/60"
            >
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">规格</span>
                <span class="text-n-slate-11">
                  {{ productSpec(row.crmProductId) || '—' }}
                </span>
              </span>
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">实时库存</span>
                <span class="text-n-slate-11">
                  {{
                    productOnHand(row.crmProductId) == null
                      ? '选料后显示'
                      : productOnHand(row.crmProductId)
                  }}
                </span>
              </span>
              <span class="inline-flex gap-1.5">
                <span class="text-n-slate-9">工程建议采购</span>
                <span class="text-n-slate-11">
                  {{ row.suggestedQty == null ? '—' : row.suggestedQty }}
                </span>
              </span>
            </div>
          </div>
        </div>
        <div
          v-if="orderTotal > 0"
          class="flex justify-end text-heading-3 text-n-slate-12"
        >
          合计：¥{{
            orderTotal.toLocaleString('zh-CN', {
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            })
          }}
        </div>
      </div>
    </Dialog>

    <MesViewDialog
      ref="viewDialogRef"
      width="5xl"
      :title="viewing ? `采购单 ${viewing.poNo}` : '采购单明细'"
      :fields="viewFields"
      items-title="采购明细"
      :item-columns="VIEW_ITEM_COLS"
      :items="viewItems"
    />

    <!-- 离屏渲染各供应商 PO 版式，供 html2canvas 截图导出 PDF（不可见、不占布局）-->
    <div class="fixed top-0 -left-[99999px] pointer-events-none">
      <div v-for="(s, i) in exportDocs" :key="i" :ref="el => setDocEl(el, i)">
        <MesPoSupplierDoc
          :data="s"
          :po-no="exportMeta.poNo"
          :date="exportMeta.date"
          :delivery-date="exportMeta.deliveryDate"
        />
      </div>
    </div>
  </div>
</template>
