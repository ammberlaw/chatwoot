<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import SalesOrderAPI from 'dashboard/api/crm/salesOrders';
import MesProductAPI from 'dashboard/api/mes/products';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'update', 'refresh']);

const { t } = useI18n();
const { accountId } = useAccount();
const dialogRef = ref(null);
const editingId = ref(null);
const orderNo = ref('');
const opportunitiesStore = useCrmOpportunitiesStore();

// 收款方式（结算方式）选项走客户设置那套可配置项，别再硬编一份。
const { paymentTermOptions, load: loadCrmOptions } = useCrmOptions();
// 收款账户：哪个银行/平台收的款。只回 id + 名字，业务员也能取。
const receiptAccounts = ref([]);
const receiptAccountOptions = computed(() => [
  { value: '', label: '请选择' },
  ...receiptAccounts.value.map(a => ({ value: String(a.id), label: a.name })),
]);
const loadReceiptAccounts = async () => {
  if (receiptAccounts.value.length) return;
  try {
    const { data } = await SalesOrderAPI.receiptAccounts();
    receiptAccounts.value = data?.payload || [];
  } catch {
    receiptAccounts.value = [];
  }
};

// 关联私海客户：仅当前业务员名下（filter=mine）的客户，用于把订单归到该客户名下统计成交额。
const privateCustomers = ref([]); // [{ id, name }]
const loadingCustomers = ref(false);
const editingCustomer = ref(null); // 编辑态原关联客户（可能已不在私海，需保留可选）
// 历史 PI 补录：PI 已在客户附件里，建单时由后端复制过来，本地没有文件对象。
const sourceAttachmentId = ref(null);

// 附件：新建时选中的文件暂存内存（pendingFiles），随创建请求一起 multipart 提交；
// 编辑时对已存在订单即时 attach/detach。
const fileInputRef = ref(null);
const pendingFiles = ref([]); // File[]（新建模式）
const attachments = ref([]); // 已保存附件（编辑模式）
const uploading = ref(false);

const today = () => new Date().toISOString().slice(0, 10);

// 销项税率：人民币单 13、美金等外币出口单 0，只在「人没手动改过」时跟着币种走。
// 用常量而不是读账套设置：业务员没有 ERP 权限、取那张表是 403。
// 账套里的「默认销项税率」只作后端兜底——历史单/导入单 tax_rate 为空时才用。
const DEFAULT_CN_TAX_RATE = 13;
const taxRateTouched = ref(false);

const form = reactive({
  name: '',
  piNo: '',
  insuranceOrderNo: '',
  paymentTerm: '',
  receiptAccountId: '',
  crmCustomerId: '',
  crmOpportunityId: '',
  status: 'IN_PRODUCTION',
  orderKind: '',
  orderDate: today(),
  deliveryDate: '',
  amount: '',
  shipping: '',
  orderCurrency: 'CNY',
  exchangeRate: '',
  taxRate: String(DEFAULT_CN_TAX_RATE),
  deliveryMethod: '',
  remark: '',
  lineItems: [], // [{ crmProductId, productLabel, name, spec, quantity, unitPrice, amount }]
});

// ── 读取 PI 自动识别 ──
const piInputRef = ref(null);
const parsingPi = ref(false);
const piMatchHint = ref(''); // 客户未匹配上时的提示（识别到的公司名）

const triggerPiUpload = () => piInputRef.value?.click();

// 把识别结果填进表单；PI 原件同时进附件（满足新建必传附件 + 留档）。
const applyParsedPi = (data, file) => {
  if (data.name) form.name = data.name;
  if (data.pi_no) form.piNo = data.pi_no;
  if (data.order_date) form.orderDate = data.order_date;
  if (data.delivery_date) form.deliveryDate = data.delivery_date;
  if (data.currency) form.orderCurrency = data.currency;
  if (data.amount != null) form.amount = String(data.amount);
  // 运费从 PI 带入：订单金额是净销售（不含运费），两者分开，别让人再去 PI 上抄一遍。
  if (data.shipping_cost != null) form.shipping = String(data.shipping_cost);
  form.lineItems = Array.isArray(data.line_items)
    ? data.line_items.map(li => ({
        crmProductId: li.crm_product_id || '',
        name: li.name || '',
        spec: li.spec || '',
        quantity: li.quantity ?? '',
        unitPrice: li.unit_price ?? '',
        amount: li.amount ?? '',
      }))
    : [];

  const c = data.customer || {};
  if (c.matched_id) {
    const idStr = String(c.matched_id);
    // 后端在「本人名下客户」里匹配，但下拉可能被 per_page 截断，未命中则补进选项保证可见。
    if (!privateCustomers.value.some(pc => String(pc.id) === idStr)) {
      privateCustomers.value = [
        ...privateCustomers.value,
        { id: c.matched_id, name: c.matched_name || c.raw_name || '客户' },
      ];
    }
    form.crmCustomerId = idStr;
    piMatchHint.value = '';
  } else {
    form.crmCustomerId = '';
    piMatchHint.value = c.raw_name
      ? t('CRM.SALES_ORDERS.PI.CUSTOMER_UNMATCHED', { name: c.raw_name })
      : '';
  }

  // 历史 PI 补录时没有本地文件对象（PI 已经在客户附件里），此时不往待上传列表塞 null。
  if (file) pendingFiles.value = [...pendingFiles.value, file];
};

const onPiSelected = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  parsingPi.value = true;
  piMatchHint.value = '';
  try {
    const fd = new FormData();
    fd.append('file', file);
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/crm/sales_orders/parse_pi`,
      fd,
      { headers: { 'Content-Type': 'multipart/form-data' } }
    );
    applyParsedPi(data, file);
    useAlert(t('CRM.SALES_ORDERS.PI.PARSE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CRM.SALES_ORDERS.PI.PARSE_ERROR')
    );
  } finally {
    parsingPi.value = false;
  }
};

// 交货方式：这单货怎么送到客户手上。仓管备货、派车、通知客户来提都看它，
// 以前只能写在备注里，出库的人还得翻备注猜。
const DELIVERY_METHOD_OPTIONS = [
  { value: '', label: '请选择' },
  { value: 'LOGISTICS', label: '物流发货' },
  { value: 'VEHICLE', label: '车辆配送' },
  { value: 'SELF_PICKUP', label: '客户自提' },
];

const addLineItem = () =>
  form.lineItems.push({
    crmProductId: '',
    name: '',
    spec: '',
    quantity: '',
    unitPrice: '',
    amount: '',
  });
const removeLineItem = index => form.lineItems.splice(index, 1);

// ── 商品编码：从产品档案选（选填）──
// 产品档案五千多条，不预载——下拉按关键词远程搜。已选中的那条并进选项里保持回显，
// 否则编辑一张老单子时下拉是空的，看着像编码丢了。
const products = ref([]);
const productOptions = computed(() =>
  products.value.map(p => ({
    value: p.id,
    label: p.sku ? `${p.name}（${p.sku}）` : p.name,
  }))
);
const mergeProducts = list => {
  list.forEach(p => {
    if (p?.id && !products.value.some(m => m.id === p.id))
      products.value.push(p);
  });
};
const searchProducts = async q => {
  try {
    const { data } = await MesProductAPI.get({ q, per_page: 30 });
    const found = data?.payload || [];
    const picked = products.value.filter(p =>
      form.lineItems.some(li => String(li.crmProductId) === String(p.id))
    );
    products.value = found;
    mergeProducts(picked);
  } catch {
    // 搜不到就维持现有选项，不打断录单
  }
};
// 选中编码后把品名/规格带出来：业务员选了产品还要再手敲一遍品名，没人会愿意。
// 只在空着时填，不覆盖他自己写的叫法（客户叫法和档案名常常不一样）。
const onProductPicked = (li, value) => {
  const p = products.value.find(x => String(x.id) === String(value));
  if (!p) return;
  if (!li.name.trim()) li.name = p.name || '';
  if (!li.spec.trim()) li.spec = p.spec || '';
};

// 上传的订单均为已付款订单，无「待确认」环节，默认从「生产中」起。
const isEditing = computed(() => editingId.value !== null);
// 订单双轨：决定这单一键转下游走哪条线（定制→生产订单 / 库存→现货出库单）。
// 金蝶过渡期它还兼当「这单在哪套系统结算」的标记，所以新建必选。
// 「未分类」只留给存量老单回显，新建时不给这个选项。
const orderKindOptions = computed(() => [
  ...(isEditing.value ? [{ value: '', label: '未分类' }] : []),
  { value: 'CUSTOM', label: '定制单' },
  { value: 'STOCK', label: '库存单' },
]);

const statusOptions = [
  { value: 'IN_PRODUCTION', label: '生产中' },
  { value: 'PENDING_SHIPMENT', label: '待出货' },
  { value: 'SHIPPED', label: '已出货' },
  { value: 'COMPLETED', label: '已完成' },
  { value: 'CANCELLED', label: '已取消' },
];

// 结算币种只保留人民币和美金：账上外币科目只开了美元一档（银行存款-美元户 /
// 应收账款-美元 / 应付账款-美元），别的币种在账里没有落脚点。
// 其他国家的币种由业务员先折成美金再录（财务 2026-10-06 定）。
const BASE_CURRENCIES = ['CNY', 'USD'];
// 历史单里还有欧元，编辑时得能显示出来，否则下拉是空白、一存就被清掉。
const currencyOptions = computed(() =>
  [
    ...BASE_CURRENCIES,
    ...(form.orderCurrency && !BASE_CURRENCIES.includes(form.orderCurrency)
      ? [form.orderCurrency]
      : []),
  ].map(v => ({ value: v, label: v }))
);

const prefillTaxRate = () => {
  if (taxRateTouched.value) return;
  form.taxRate =
    form.orderCurrency === 'CNY' ? String(DEFAULT_CN_TAX_RATE) : '0';
};
const onCurrencyChange = v => {
  form.orderCurrency = v;
  prefillTaxRate();
};

const customerOptions = computed(() =>
  privateCustomers.value.map(c => ({
    value: String(c.id),
    label: c.name,
    // 搜索也命中联系人/邮箱/电话（不改显示标签）。
    searchText: [c.contactName, c.contactEmail, c.contactPhone]
      .filter(Boolean)
      .join(' '),
  }))
);

// 编辑态原客户若已不在私海列表（转公海/换负责人），用 displayLabel 兜底显示，避免变空白。
const customerDisplayLabel = computed(() => {
  if (!editingCustomer.value) return '';
  const id = String(editingCustomer.value.id);
  if (customerOptions.value.some(o => o.value === id)) return '';
  return `${editingCustomer.value.name}（非私海）`;
});

// 关联商机：选了客户则只显示该客户的商机，否则显示全部
const opportunityOptions = computed(() => {
  const records = opportunitiesStore.getRecords || [];
  const filtered = form.crmCustomerId
    ? records.filter(
        o => String(o.crmCustomerId) === String(form.crmCustomerId)
      )
    : records;
  return [
    { value: '', label: '— 无 —' },
    ...filtered.map(o => ({ value: String(o.id), label: o.name })),
  ];
});

// 一行明细算不算填好了：品名、数量、单价三样齐了才算。
// 只填品名不填数量单价，审核的人照样不知道这单值多少钱、发几台。
const isLineItemFilled = li =>
  (li.name || '').trim() &&
  Number(li.quantity) > 0 &&
  li.unitPrice !== '' &&
  li.unitPrice !== null &&
  Number(li.unitPrice) >= 0;

// 订单明细必填（2026-10-22）：以前明细可以一行不填，审核人打开只看到一个金额，
// 不知道卖的是什么货。生产上 365 张单里 15 张是空的，审核时只能退回去问业务员。
const filledLineItems = computed(() => form.lineItems.filter(isLineItemFilled));
const hasIncompleteLineItem = computed(() =>
  form.lineItems.some(
    li =>
      !isLineItemFilled(li) &&
      ((li.name || '').trim() ||
        li.quantity !== '' ||
        li.unitPrice !== '' ||
        li.crmProductId)
  )
);

// 新建订单：附件、订单类型、订单明细、结算方式、收款账户必填（附件如 PI、生产订单）。
// 这几项只在**新建**时卡：生产上 9 月前的老单九成这两栏是空的（367 张里 329 张没结算方式），
// 编辑时一并卡死，业务员想改个交期都得先补两栏历史信息——那不是补数据，是挡着他干活。
// 老单缺什么，详情面板上照常标出来，补不补由审核人和他自己决定。
const isFormInvalid = computed(
  () =>
    !form.name.trim() ||
    !form.orderDate ||
    hasIncompleteLineItem.value ||
    (!isEditing.value &&
      (filledLineItems.value.length === 0 ||
        !form.orderKind ||
        !form.paymentTerm ||
        !form.receiptAccountId ||
        !form.deliveryMethod ||
        (pendingFiles.value.length === 0 && !sourceAttachmentId.value)))
);

const resetForm = () => {
  editingId.value = null;
  sourceAttachmentId.value = null;
  orderNo.value = '';
  editingCustomer.value = null;
  pendingFiles.value = [];
  attachments.value = [];
  piMatchHint.value = '';
  form.name = '';
  form.piNo = '';
  form.insuranceOrderNo = '';
  form.paymentTerm = '';
  form.receiptAccountId = '';
  form.crmCustomerId = '';
  form.crmOpportunityId = '';
  form.status = 'IN_PRODUCTION';
  form.orderKind = '';
  form.orderDate = today();
  form.deliveryDate = '';
  form.amount = '';
  form.shipping = '';
  form.orderCurrency = 'CNY';
  form.exchangeRate = '';
  taxRateTouched.value = false;
  form.taxRate = String(DEFAULT_CN_TAX_RATE);
  form.remark = '';
  form.lineItems = [];
  form.deliveryMethod = '';
  products.value = [];
};

// 拉取当前业务员名下私海客户（一次拿全）。
const loadPrivateCustomers = async () => {
  loadingCustomers.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { filter: 'mine_shared', per_page: 200 } }
    );
    privateCustomers.value = (data.payload || []).map(c => ({
      id: c.id,
      name: c.name,
      contactName: c.primary_contact_name,
      contactEmail: c.contact_email,
      contactPhone: c.contact_phone,
    }));
  } catch {
    privateCustomers.value = [];
  } finally {
    loadingCustomers.value = false;
  }
};

// 用「已识别的 PI」预填后打开（历史 PI 补录走这条）：客户直接取附件所属客户，
// 不再走 PI 里客户名的模糊匹配——附件本来就挂在这个客户下，比猜准。
const openWithParsedPi = ({ parsed, customer }) => {
  resetForm();
  applyParsedPi(parsed, null);
  sourceAttachmentId.value = parsed?.attachment_id || null;
  if (customer?.id) {
    const idStr = String(customer.id);
    if (!privateCustomers.value.some(pc => String(pc.id) === idStr)) {
      privateCustomers.value = [
        ...privateCustomers.value,
        { id: customer.id, name: customer.name || '客户' },
      ];
    }
    form.crmCustomerId = idStr;
    piMatchHint.value = '';
  }
  loadCrmOptions('payment_term');
  loadReceiptAccounts();
  dialogRef.value?.open();
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    orderNo.value = record.orderNo || '';
    attachments.value = record.files || [];
    editingCustomer.value = record.crmCustomerId
      ? { id: record.crmCustomerId, name: record.customerName || '客户' }
      : null;
    form.name = record.name || '';
    form.piNo = record.piNo || '';
    form.lineItems = Array.isArray(record.lineItems)
      ? record.lineItems.map(li => ({
          crmProductId: li.crmProductId || '',
          name: li.name || '',
          spec: li.spec || '',
          quantity: li.quantity ?? '',
          unitPrice: li.unitPrice ?? '',
          amount: li.amount ?? '',
        }))
      : [];
    // 已选的产品补进下拉选项，不然编辑时那一栏是空的（下拉是远程搜，不预载）。
    mergeProducts(
      (record.lineItems || [])
        .filter(li => li.crmProductId)
        .map(li => ({
          id: li.crmProductId,
          name: li.productName || li.name,
          sku: li.sku,
        }))
    );
    form.crmCustomerId = record.crmCustomerId
      ? String(record.crmCustomerId)
      : '';
    form.crmOpportunityId = record.crmOpportunityId
      ? String(record.crmOpportunityId)
      : '';
    form.status = record.status || 'IN_PRODUCTION';
    form.orderKind = record.orderKind || '';
    form.orderDate = record.orderDate ? record.orderDate.slice(0, 10) : today();
    form.deliveryDate = record.deliveryDate
      ? record.deliveryDate.slice(0, 10)
      : '';
    form.amount = record.orderAmountMicros
      ? String(record.orderAmountMicros / 1_000_000)
      : '';
    form.shipping = record.shippingMicros
      ? String(record.shippingMicros / 1_000_000)
      : '';
    form.orderCurrency = record.orderCurrency || 'CNY';
    form.exchangeRate =
      record.exchangeRate != null ? String(record.exchangeRate) : '';
    // 存量单的税率是迁移按币种刷进去的，载入后视作「已填」，别被币种联动改掉
    taxRateTouched.value = true;
    form.taxRate = record.taxRate != null ? String(record.taxRate) : '';
    form.remark = record.remark || '';
    form.insuranceOrderNo = record.insuranceOrderNo || '';
    form.paymentTerm = record.paymentTerm || '';
    form.receiptAccountId = record.receiptAccountId
      ? String(record.receiptAccountId)
      : '';
    form.deliveryMethod = record.deliveryMethod || '';
  }
  loadCrmOptions('payment_term');
  loadReceiptAccounts();
  loadPrivateCustomers();
  if (!opportunitiesStore.getRecords.length) {
    // 后端读 per_page（下划线）；驼峰 perPage 不生效会回落到每页 15 条，商机选择器漏项。
    opportunitiesStore.get({ page: 1, per_page: 100 });
  }
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  // 明细以 snake_case 键序列化成 JSON 字符串（multipart 建单无法带嵌套数组），后端解析入 line_items。
  const num = v => {
    if (v === '' || v === null || v === undefined) return null;
    const n = parseFloat(v);
    return Number.isNaN(n) ? null : n;
  };
  const lineItemsPayload = form.lineItems
    .map(li => ({
      crm_product_id: li.crmProductId || null,
      name: (li.name || '').trim(),
      spec: (li.spec || '').trim(),
      quantity: num(li.quantity),
      unit_price: num(li.unitPrice),
      amount: num(li.amount),
    }))
    .filter(li => li.name);

  const payload = {
    name: form.name.trim(),
    piNo: form.piNo.trim() || null,
    insuranceOrderNo: form.insuranceOrderNo.trim() || null,
    paymentTerm: form.paymentTerm || null,
    receiptAccountId: form.receiptAccountId || null,
    deliveryMethod: form.deliveryMethod || null,
    crmCustomerId: form.crmCustomerId || null,
    crmOpportunityId: form.crmOpportunityId || null,
    status: form.status,
    orderKind: form.orderKind || null,
    orderDate: form.orderDate,
    deliveryDate: form.deliveryDate || null,
    orderAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    shippingMicros: form.shipping
      ? Math.round(parseFloat(form.shipping) * 1_000_000)
      : null,
    orderCurrency: form.orderCurrency,
    exchangeRate: form.exchangeRate ? parseFloat(form.exchangeRate) : null,
    taxRate: form.taxRate === '' ? null : parseInt(form.taxRate, 10),
    remark: form.remark.trim() || null,
    lineItemsJson: JSON.stringify(lineItemsPayload),
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', {
      ...payload,
      sourceAttachmentId: sourceAttachmentId.value || undefined,
      __files: pendingFiles.value,
    });
  }
};

// ── 附件 ──
const triggerUpload = () => fileInputRef.value?.click();

const attachApi = () =>
  `/api/v1/accounts/${accountId.value}/crm/sales_orders/${editingId.value}/attach`;

const onFilesSelected = async event => {
  const files = Array.from(event.target.files || []);
  event.target.value = '';
  if (!files.length) return;

  // 新建模式：暂存内存，随创建一起提交。
  if (!isEditing.value) {
    pendingFiles.value = [...pendingFiles.value, ...files];
    return;
  }

  // 编辑模式：即时上传到已存在订单。
  uploading.value = true;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  try {
    const { data } = await axios.post(attachApi(), fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    attachments.value = data.files || [];
    emit('refresh');
    useAlert(t('CRM.SALES_ORDERS.ATTACH.UPLOAD_SUCCESS'));
  } catch {
    useAlert(t('CRM.SALES_ORDERS.ATTACH.UPLOAD_ERROR'));
  } finally {
    uploading.value = false;
  }
};

const removePending = index => {
  pendingFiles.value = pendingFiles.value.filter((_, i) => i !== index);
};

const removeAttachment = async id => {
  try {
    const { data } = await axios.delete(`${attachApi()}/${id}`);
    attachments.value = data.files || [];
    emit('refresh');
  } catch {
    useAlert(t('CRM.SALES_ORDERS.ATTACH.DELETE_ERROR'));
  }
};

const prettySize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

defineExpose({ dialogRef, onSuccess, open, openWithParsedPi });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    confirm-button-color="iris"
    :title="
      isEditing
        ? t('CRM.SALES_ORDERS.EDIT.TITLE')
        : t('CRM.SALES_ORDERS.CREATE.TITLE')
    "
    :description="t('CRM.SALES_ORDERS.CREATE.DESCRIPTION')"
    :is-loading="isLoading"
    :disable-confirm-button="isFormInvalid"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <!-- 读取 PI 自动识别（仅新建）：上传 PDF/Excel，自动填客户/PI号/金额/明细 -->
      <div
        v-if="!isEditing"
        class="crm-ai-box flex items-center justify-between gap-3 p-3 border border-dashed rounded-lg border-n-iris-6 bg-n-iris-2"
      >
        <div class="flex items-center gap-2 text-sm text-n-slate-11">
          <span class="i-ph-sparkle-fill size-4 text-n-iris-9" />
          {{ t('CRM.SALES_ORDERS.PI.HINT') }}
        </div>
        <button
          type="button"
          class="crm-ai crm-ai-solid flex items-center gap-1.5 h-8 px-3 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
          :disabled="parsingPi"
          @click="triggerPiUpload"
        >
          <span
            class="size-4"
            :class="
              parsingPi
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-ph-sparkle-fill'
            "
          />
          {{
            parsingPi
              ? t('CRM.SALES_ORDERS.PI.PARSING')
              : t('CRM.SALES_ORDERS.PI.UPLOAD')
          }}
        </button>
        <input
          ref="piInputRef"
          type="file"
          accept=".pdf,.xlsx,.xls,.csv"
          class="hidden"
          @change="onPiSelected"
        />
      </div>

      <div
        class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        {{ t('CRM.SALES_ORDERS.FORM.SECTION_BASIC') }}
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col col-span-2 min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.NAME') }}
            <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="form.name" autofocus />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.PI_NO') }}
          </label>
          <Input v-model="form.piNo" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            信保订单号
          </label>
          <Input v-model="form.insuranceOrderNo" />
        </div>
        <div v-if="isEditing" class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.ORDER_NO') }}
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm rounded-lg bg-n-slate-3 text-n-slate-11"
          >
            {{ orderNo }}
          </div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.CUSTOMER') }}
          </label>
          <ComboBox
            v-model="form.crmCustomerId"
            :options="customerOptions"
            :display-label="customerDisplayLabel"
            :placeholder="
              loadingCustomers
                ? t('CRM.SALES_ORDERS.FORM.CUSTOMER_LOADING')
                : t('CRM.SALES_ORDERS.FORM.CUSTOMER_PLACEHOLDER')
            "
            :search-placeholder="t('CRM.SALES_ORDERS.FORM.CUSTOMER_SEARCH')"
            :empty-state="t('CRM.SALES_ORDERS.FORM.CUSTOMER_EMPTY')"
          />
          <p v-if="piMatchHint" class="text-xs text-n-amber-11">
            {{ piMatchHint }}
          </p>
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.OPPORTUNITY') }}
          </label>
          <SelectCard
            v-model="form.crmOpportunityId"
            :options="opportunityOptions"
          />
        </div>
      </div>

      <div class="grid grid-cols-4 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.STATUS') }}
          </label>
          <SelectCard v-model="form.status" :options="statusOptions" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            订单类型
            <span v-if="!isEditing" class="text-n-ruby-11">*</span>
          </label>
          <SelectCard v-model="form.orderKind" :options="orderKindOptions" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.ORDER_DATE') }}
          </label>
          <DatePicker v-model="form.orderDate" block />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.DELIVERY_DATE') }}
          </label>
          <DatePicker v-model="form.deliveryDate" block />
        </div>
      </div>

      <div
        class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        {{ t('CRM.SALES_ORDERS.FORM.SECTION_AMOUNT') }}
      </div>
      <div class="grid grid-cols-4 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.AMOUNT')"
        />
        <Input
          v-model="form.shipping"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.SHIPPING')"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.CURRENCY') }}
          </label>
          <SelectCard
            :model-value="form.orderCurrency"
            :options="currencyOptions"
            @update:model-value="onCurrencyChange"
          />
        </div>
        <Input
          v-model="form.exchangeRate"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.EXCHANGE_RATE')"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12"
            >销项税率（%）</label
          >
          <Input
            :model-value="form.taxRate"
            type="number"
            min="0"
            max="100"
            @update:model-value="
              v => {
                form.taxRate = v;
                taxRateTouched = true;
              }
            "
          />
          <span class="text-xs text-n-slate-11">
            人民币单默认 13、外币出口单默认 0，可改；为 0
            时出库凭证不出销项税行。
          </span>
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            结算方式
            <span v-if="!isEditing" class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="form.paymentTerm"
            :options="paymentTermOptions"
          />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            收款账户
            <span v-if="!isEditing" class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="form.receiptAccountId"
            :options="receiptAccountOptions"
          />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            交货方式
            <span v-if="!isEditing" class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="form.deliveryMethod"
            :options="DELIVERY_METHOD_OPTIONS"
          />
        </div>
      </div>

      <TextArea
        v-model="form.remark"
        :label="t('CRM.SALES_ORDERS.FORM.REMARK')"
      />

      <!-- 订单明细（PI 识别自动填入，可增删改）-->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span
            class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
          >
            <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
            {{ t('CRM.SALES_ORDERS.FORM.SECTION_ITEMS') }}
            <span
              v-if="!isEditing"
              class="font-normal normal-case text-n-ruby-11"
            >
              必填
            </span>
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="addLineItem"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('CRM.SALES_ORDERS.ITEMS.ADD') }}
          </button>
        </div>

        <!-- 明细仍是必填（提交按钮会灰掉），只是不再摆那句长提示——
             表头的红星已经说明必填，再写一段话是重复。
             ⚠️ 这里必须是 v-if 不是 v-else：原来配对的那个 v-if 提示块已经删掉了。 -->
        <div v-if="form.lineItems.length" class="flex flex-col gap-2">
          <div
            v-for="(li, index) in form.lineItems"
            :key="index"
            class="flex items-start gap-2 pb-2 border-b border-dashed last:border-0 last:pb-0 border-n-weak"
          >
            <div class="grid flex-1 min-w-0 grid-cols-6 gap-2">
              <ComboBox
                v-model="li.crmProductId"
                class="col-span-3"
                :options="productOptions"
                placeholder="搜索产品名称 / 编码（选填）"
                use-api-results
                clearable
                empty-state="没搜到这个产品，直接在右边手写品名就行"
                @open="searchProducts('')"
                @search="searchProducts"
                @update:model-value="val => onProductPicked(li, val)"
              />
              <Input
                v-model="li.name"
                class="col-span-3"
                :placeholder="t('CRM.SALES_ORDERS.ITEMS.NAME')"
              />
              <Input
                v-model="li.spec"
                class="col-span-3"
                :placeholder="t('CRM.SALES_ORDERS.ITEMS.SPEC')"
              />
              <Input
                v-model="li.quantity"
                type="number"
                :placeholder="t('CRM.SALES_ORDERS.ITEMS.QTY')"
              />
              <Input
                v-model="li.unitPrice"
                type="number"
                :placeholder="t('CRM.SALES_ORDERS.ITEMS.PRICE')"
              />
              <Input
                v-model="li.amount"
                type="number"
                :placeholder="t('CRM.SALES_ORDERS.ITEMS.AMOUNT')"
              />
            </div>
            <button
              type="button"
              class="flex items-center justify-center w-6 h-10 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
              :title="t('CRM.SALES_ORDERS.ITEMS.REMOVE')"
              @click="removeLineItem(index)"
            >
              <span class="i-lucide-x size-4 shrink-0" />
            </button>
          </div>
          <span
            v-if="hasIncompleteLineItem"
            class="px-1 text-xs text-n-ruby-11"
          >
            有明细行没填完——品名、数量、单价三样都要有，不要的整行删掉。
          </span>
        </div>
      </div>

      <!-- 附件（新建必填：PI / 生产订单）-->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span
            class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            {{ t('CRM.SALES_ORDERS.ATTACH.TITLE') }}
            <span v-if="!isEditing" class="text-n-ruby-11">*</span>
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="uploading"
            @click="triggerUpload"
          >
            <span class="i-lucide-paperclip size-4" />
            {{
              uploading
                ? t('CRM.SALES_ORDERS.ATTACH.UPLOADING')
                : t('CRM.SALES_ORDERS.ATTACH.ADD')
            }}
          </button>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onFilesSelected"
          />
        </div>

        <div
          v-if="!isEditing && pendingFiles.length === 0 && !sourceAttachmentId"
          class="text-xs text-n-ruby-11"
        >
          {{ t('CRM.SALES_ORDERS.ATTACH.REQUIRED_HINT') }}
        </div>
        <div
          v-else-if="isEditing && !attachments.length"
          class="text-xs text-n-slate-10"
        >
          {{ t('CRM.SALES_ORDERS.ATTACH.EMPTY_HINT') }}
        </div>

        <!-- 待提交文件（新建模式）-->
        <div
          v-for="(file, index) in pendingFiles"
          :key="`pending-${index}`"
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <span class="flex items-center gap-2 text-sm text-n-slate-12">
            <span class="i-lucide-file size-4" />
            {{ file.name }}
            <span class="text-xs text-n-slate-10">{{
              prettySize(file.size)
            }}</span>
          </span>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            :title="t('CRM.SALES_ORDERS.ATTACH.REMOVE')"
            @click="removePending(index)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <!-- 已保存附件（编辑模式）-->
        <div
          v-for="file in attachments"
          :key="file.id"
          class="flex items-center justify-between px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <a
            :href="file.url"
            target="_blank"
            rel="noopener"
            class="flex items-center gap-2 text-sm text-n-blue-11 hover:underline"
          >
            <span class="i-lucide-file size-4" />
            {{ file.filename }}
            <span class="text-xs text-n-slate-10">{{
              prettySize(file.byte_size)
            }}</span>
          </a>
          <button
            type="button"
            class="text-n-slate-10 hover:text-n-ruby-11"
            :title="t('CRM.SALES_ORDERS.ATTACH.REMOVE')"
            @click="removeAttachment(file.id)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>
    </div>
  </Dialog>
</template>
