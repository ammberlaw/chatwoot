<script setup>
/* global axios */
import { computed, nextTick, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import KnowledgeDocAPI from 'dashboard/api/crm/knowledgeDocs';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import PisAPI from 'dashboard/api/crm/pis';
import PiSellerProfileAPI from 'dashboard/api/crm/piSellerProfiles';
import SalesOrderAPI from 'dashboard/api/crm/salesOrders';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CrmKnowledgeImagePicker from './CrmKnowledgeImagePicker.vue';

import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

const emit = defineEmits(['saved']);

const { t } = useI18n();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const dialogRef = ref(null);
const editingId = ref(null);
const saving = ref(false);

const DEFAULT_TERMS =
  '1. Delivery time: 30 working days after receiving the payment.\n2. Payment terms: BANK / Alibaba. 100% in advance.';

const today = () => new Date().toISOString().slice(0, 10);

const blankForm = () => ({
  piNo: '',
  piDate: today(),
  status: 'DRAFT',
  currency: 'USD',
  crmCustomerId: '',
  companyHeader: '',
  attention: '',
  buyerCompany: '',
  buyerAddress: '',
  buyerEmail: '',
  buyerTel: '',
  buyerEori: '',
  portOfShipment: 'DongGuan, China',
  portOfDestination: '',
  countryOfOrigin: 'China',
  shippingMethod: 'UPS',
  shippingCostLabel: 'SHIPPING COST',
  shippingCost: '',
  terms: DEFAULT_TERMS,
  issuedBy: '',
  sellerMobile: '',
  sellerEmail: '',
  remark: '',
  items: [],
});

const form = reactive(blankForm());
// 做到一半点了别处就整张 PI 没了（用户原话：「再回页面的时候，就变空白了」）。
// 接上全站那套未保存守卫：点 X / 取消 / 点外部 / Esc 都会先问一句，而不是直接丢掉。
// pictureUrl 是上传后服务端回的地址，不算用户改动。
const { isDirty, markPristine } = useDirtyGuard(() => form, {
  ignore: ['pictureUrl'],
});

const statusOptions = [
  { value: 'DRAFT', label: t('CRM.PI.STATUS.DRAFT') },
  // 未付款：PI 已经发给客户、钱还没到。业务员自己不掌握收款（金额走财务对账），
  // 没这一档就只能一直挂「草稿」，看不出「待收款」和「还没做完」的区别。
  { value: 'UNPAID', label: t('CRM.PI.STATUS.UNPAID') },
  { value: 'PAID', label: t('CRM.PI.STATUS.PAID') },
  { value: 'VOID', label: t('CRM.PI.STATUS.VOID') },
];
const currencyOptions = ['USD', 'CNY', 'EUR'].map(v => ({
  value: v,
  label: v,
}));

// ── 客户下拉（本业务员名下） + 选中预填买方快照 ──
const customers = ref([]);
const loadingCustomers = ref(false);
const editingCustomerLabel = ref('');
const customerOptions = computed(() =>
  customers.value.map(c => ({
    value: String(c.id),
    label: c.name,
    // 搜索也命中联系人/邮箱/电话（不改显示标签）。
    searchText: [c.contactName, c.contactEmail, c.contactPhone]
      .filter(Boolean)
      .join(' '),
  }))
);
// 客户可能数千条（小满迁入），改服务端搜索：按私海可见口径（你在私海能看到的都能选，
// 含管理员/主管看到的本团队客户），输入即查后端，避免旧版一次性取 200 条后本地搜、超出就选不到。
const loadCustomers = async (q = '') => {
  loadingCustomers.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { filter: 'private', q: q || undefined, per_page: 50 } }
    );
    customers.value = (data.payload || []).map(c => ({
      id: c.id,
      name: c.name,
      contactName: c.primary_contact_name,
      contactEmail: c.contact_email,
      contactPhone: c.contact_phone,
    }));
  } catch {
    customers.value = [];
  } finally {
    loadingCustomers.value = false;
  }
};
let customerSearchTimer = null;
const onCustomerSearch = q => {
  clearTimeout(customerSearchTimer);
  customerSearchTimer = setTimeout(() => loadCustomers(q), 250);
};
const onCustomerOpen = () => {
  if (!customers.value.length) loadCustomers();
};

const onCustomerChange = async id => {
  form.crmCustomerId = id;
  if (!id) return;
  try {
    const { data } = await PisAPI.prefill(accountId.value, id);
    form.attention = data.attention || form.attention;
    form.buyerCompany = data.buyer_company || form.buyerCompany;
    form.buyerAddress = data.buyer_address || form.buyerAddress;
    form.buyerEmail = data.buyer_email || form.buyerEmail;
    form.buyerTel = data.buyer_tel || form.buyerTel;
    form.portOfDestination = data.port_of_destination || form.portOfDestination;
  } catch {
    // 预填失败不阻断，业务可手填
  }
};

// ── 上传 PI 自动识别（与订单自动填单同引擎）：填 PI号/日期/币种/客户/明细 ──
const piInputRef = ref(null);
const parsingPi = ref(false);
const piMatchHint = ref(''); // 客户未匹配上时的提示（识别到的公司名）
const triggerPiUpload = () => piInputRef.value?.click();

const applyParsedPi = data => {
  if (data.pi_no) form.piNo = data.pi_no;
  if (data.order_date) form.piDate = data.order_date;
  if (data.currency) form.currency = data.currency;
  form.items = Array.isArray(data.line_items)
    ? data.line_items.map(li => ({
        id: null,
        model: li.name || '',
        description: li.spec || '',
        quantity: li.quantity ?? '',
        unitPrice: li.unit_price ?? '',
        pictureUrl: null,
        pictureFile: null,
        pictureSignedId: '',
        pictureSignedId: '',
        pictureSignedId: '',
      }))
    : [];

  const c = data.customer || {};
  if (c.matched_id) {
    const idStr = String(c.matched_id);
    if (!customers.value.some(pc => String(pc.id) === idStr)) {
      customers.value = [
        ...customers.value,
        { id: c.matched_id, name: c.matched_name || c.raw_name || '客户' },
      ];
    }
    editingCustomerLabel.value = c.matched_name || c.raw_name || '';
    onCustomerChange(idStr); // 带出买方快照
    piMatchHint.value = '';
  } else {
    piMatchHint.value = c.raw_name
      ? t('CRM.PI.PI.CUSTOMER_UNMATCHED', { name: c.raw_name })
      : '';
  }
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
    const { data } = await PisAPI.parsePi(accountId.value, fd);
    applyParsedPi(data);
    useAlert(t('CRM.PI.PI.PARSE_SUCCESS'));
  } catch (error) {
    useAlert(error?.response?.data?.error || t('CRM.PI.PI.PARSE_ERROR'));
  } finally {
    parsingPi.value = false;
  }
};

// ── 公司抬头（3选1的公司主体：导出时公司名/地址/银行按此填） ──
const companyHeaderOptions = ref([]);
const loadCompanyHeaders = async () => {
  if (companyHeaderOptions.value.length) return;
  try {
    const { data } = await PisAPI.companyHeaders(accountId.value);
    companyHeaderOptions.value = (data || []).map(h => ({
      value: h.key,
      label: h.name,
    }));
  } catch {
    companyHeaderOptions.value = [];
  }
};

// ── 明细 ──
const num = v => {
  if (v === '' || v === null || v === undefined) return null;
  const n = parseFloat(v);
  return Number.isNaN(n) ? null : n;
};
const rowAmount = it => {
  const q = num(it.quantity);
  const p = num(it.unitPrice);
  return q != null && p != null ? q * p : null;
};
const grandTotal = computed(() => {
  const items = form.items.reduce((s, it) => s + (rowAmount(it) || 0), 0);
  return items + (num(form.shippingCost) || 0);
});
const fmtAmount = v =>
  v == null
    ? '—'
    : `${form.currency} ${v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const addItem = () =>
  form.items.push({
    id: null,
    model: '',
    description: '',
    quantity: '',
    unitPrice: '',
    pictureUrl: null,
    pictureFile: null,
    pictureSignedId: '',
  });
const removeItem = i => form.items.splice(i, 1);

const itemPicInputs = ref({});
const triggerItemPic = i => itemPicInputs.value[i]?.click();
const onItemPic = (event, i) => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  form.items[i].pictureFile = file;
  form.items[i].pictureSignedId = '';
  form.items[i].pictureUrl = URL.createObjectURL(file);
};

// 从知识库选图：后端把原图复制成独立一份再给 signed_id，
// 知识库原件之后换掉或删掉，已发出去的 PI 不受影响（见 Crm::KnowledgeDocSnapshot）。
const pickerRow = ref(null);
const pickerRef = ref(null);
const openPicker = i => {
  pickerRow.value = i;
  pickerRef.value?.open();
};
const onPickFromLibrary = async img => {
  const i = pickerRow.value;
  if (i == null) return;
  try {
    const { data } = await KnowledgeDocAPI.snapshotFiles([img.attachment_id]);
    const snap = data.payload?.[0];
    if (!snap) throw new Error('empty');
    form.items[i].pictureFile = null;
    form.items[i].pictureSignedId = snap.signed_id;
    form.items[i].pictureUrl = img.url;
  } catch {
    useAlert('这张图取用失败，换一张或改用本地上传');
  }
};

const reset = () => {
  editingId.value = null;
  editingCustomerLabel.value = '';
  piMatchHint.value = '';
  Object.assign(form, blankForm());
  form.issuedBy = currentUser.value?.name || '';
};

// 新建时用「我的卖方信息」预录带入卖方落款（联系人/手机/邮箱），本单仍可改。
const loadSellerDefaults = async () => {
  try {
    const { data } = await PiSellerProfileAPI.get();
    form.issuedBy = data.contact_name || form.issuedBy;
    form.sellerMobile = data.mobile || '';
    form.sellerEmail = data.email || '';
  } catch {
    // 无预录/失败：留空，导出时后端会拦并提示先填
  }
};

const open = record => {
  reset();
  if (!record) addItem(); // 新建默认给一行产品，免得每次手动「加一行」
  loadCustomers();
  loadCompanyHeaders().then(() => {
    if (!editingId.value && !form.companyHeader) {
      form.companyHeader = companyHeaderOptions.value[0]?.value || '';
    }
  });
  if (record) {
    editingId.value = record.id;
    editingCustomerLabel.value = record.customerName || '';
    form.piNo = record.piNo || '';
    form.piDate = record.piDate ? record.piDate.slice(0, 10) : today();
    form.status = record.status || 'DRAFT';
    form.currency = record.currency || 'USD';
    form.crmCustomerId = record.crmCustomerId
      ? String(record.crmCustomerId)
      : '';
    form.companyHeader = record.companyHeader || '';
    form.attention = record.attention || '';
    form.buyerCompany = record.buyerCompany || '';
    form.buyerAddress = record.buyerAddress || '';
    form.buyerEmail = record.buyerEmail || '';
    form.buyerTel = record.buyerTel || '';
    form.buyerEori = record.buyerEori || '';
    form.portOfShipment = record.portOfShipment || '';
    form.portOfDestination = record.portOfDestination || '';
    form.countryOfOrigin = record.countryOfOrigin || '';
    form.shippingMethod = record.shippingMethod || '';
    form.shippingCostLabel = record.shippingCostLabel || '';
    form.shippingCost =
      record.shippingCostMicros != null
        ? String(record.shippingCostMicros / 1_000_000)
        : '';
    form.terms = record.terms || '';
    form.issuedBy = record.issuedBy || '';
    form.sellerMobile = record.sellerMobile || '';
    form.sellerEmail = record.sellerEmail || '';
    form.remark = record.remark || '';
    form.items = (record.items || []).map(it => ({
      id: it.id,
      model: it.model || '',
      description: it.description || '',
      quantity: it.quantity != null ? it.quantity : '',
      unitPrice:
        it.unitPriceMicros != null ? it.unitPriceMicros / 1_000_000 : '',
      pictureUrl: it.pictureUrl || null,
      pictureFile: null,
      pictureSignedId: '',
      pictureSignedId: '',
    }));
  } else {
    loadSellerDefaults();
  }
  dialogRef.value?.open();
  // 回填完再取基线，否则刚打开就被判成「已修改」。
  nextTick(markPristine);
};

const isValid = computed(() => !!form.piDate);

const toMicros = v => {
  const n = num(v);
  return n == null ? '' : String(Math.round(n * 1_000_000));
};

const buildFormData = () => {
  const fd = new FormData();
  const set = (k, v) => fd.append(`pi[${k}]`, v ?? '');
  if (form.piNo.trim()) set('pi_no', form.piNo.trim());
  set('pi_date', form.piDate);
  set('status', form.status);
  set('currency', form.currency);
  set('crm_customer_id', form.crmCustomerId || '');
  set('company_header', form.companyHeader);
  set('attention', form.attention);
  set('buyer_company', form.buyerCompany);
  set('buyer_address', form.buyerAddress);
  set('buyer_email', form.buyerEmail);
  set('buyer_tel', form.buyerTel);
  set('buyer_eori', form.buyerEori);
  set('port_of_shipment', form.portOfShipment);
  set('port_of_destination', form.portOfDestination);
  set('country_of_origin', form.countryOfOrigin);
  set('shipping_method', form.shippingMethod);
  set('shipping_cost_label', form.shippingCostLabel);
  set('shipping_cost_micros', toMicros(form.shippingCost));
  set('terms', form.terms);
  set('issued_by', form.issuedBy);
  set('seller_mobile', form.sellerMobile);
  set('seller_email', form.sellerEmail);
  set('remark', form.remark);

  form.items.forEach((it, i) => {
    const p = `pi[pi_items_attributes][${i}]`;
    if (it.id) fd.append(`${p}[id]`, it.id);
    fd.append(`${p}[position]`, i);
    fd.append(`${p}[model]`, it.model || '');
    fd.append(`${p}[description]`, it.description || '');
    fd.append(`${p}[quantity]`, num(it.quantity) ?? '');
    fd.append(`${p}[unit_price_micros]`, toMicros(it.unitPrice));
    if (it.pictureFile) {
      fd.append(`${p}[picture]`, it.pictureFile);
    } else if (it.pictureSignedId) {
      fd.append(`${p}[picture]`, it.pictureSignedId);
    }
  });
  return fd;
};

// ── 转单后补填结算信息 ──
// PI 是发给客户的单据，结算方式/信保单号不录在 PI 上（用户定调）；
// 收款账户按 PI 抬头在后端自动带入，剩下两项转单那一刻就地补，不然自动转出来的单永远是空的。
const settlementRef = ref(null);
const convertedOrder = reactive({ id: null, no: '', missing: [] });
const settlement = reactive({
  paymentTerm: '',
  receiptAccountId: '',
  deliveryMethod: '',
  insuranceOrderNo: '',
});
// 交货方式：这单货怎么送到客户手上。仓管备货、派车、通知客户来提都看它。
const DELIVERY_METHOD_OPTIONS = [
  { value: '', label: '请选择' },
  { value: 'LOGISTICS', label: '物流发货' },
  { value: 'VEHICLE', label: '车辆配送' },
  { value: 'SELF_PICKUP', label: '客户自提' },
];
const savingSettlement = ref(false);
// 红星那两项填齐了才能点保存。要么填完存，要么「稍后再补」——不留「填一半存进去」
// 这条路，否则红星就成了摆设，人照样会在转 ERP 那一步才发现缺东西。
// 收款账户只在后端报它缺的时候才算必填：没缺时那一栏是「已按 PI 抬头带入」的只读块，
// 没有下拉可选，再要求它就是让人点不动保存又不知道该点哪。
const isSettlementInvalid = computed(
  () =>
    !settlement.paymentTerm ||
    !settlement.deliveryMethod ||
    (convertedOrder.missing.includes('receipt_account_id') &&
      !settlement.receiptAccountId)
);
// 收款水单这类单据：选了先放内存，点保存时跟结算信息一起提交到订单附件
const settlementFiles = ref([]);
const settlementFileRef = ref(null);
const pickSettlementFiles = () => settlementFileRef.value?.click();
const onSettlementFiles = event => {
  settlementFiles.value = [
    ...settlementFiles.value,
    ...Array.from(event.target.files || []),
  ];
  event.target.value = '';
};
const removeSettlementFile = i => {
  settlementFiles.value = settlementFiles.value.filter((_, idx) => idx !== i);
};
const { paymentTermOptions, load: loadCrmOptions } = useCrmOptions();
const receiptAccounts = ref([]);
const receiptAccountOptions = computed(() => [
  { value: '', label: '请选择' },
  ...receiptAccounts.value.map(a => ({ value: String(a.id), label: a.name })),
]);

const openSettlement = async ({ id, no, missing }) => {
  convertedOrder.id = id;
  convertedOrder.no = no;
  convertedOrder.missing = missing || [];
  settlement.paymentTerm = '';
  settlement.receiptAccountId = '';
  settlement.deliveryMethod = '';
  settlement.insuranceOrderNo = '';
  settlementFiles.value = [];
  loadCrmOptions('payment_term');
  try {
    const { data } = await SalesOrderAPI.receiptAccounts();
    receiptAccounts.value = data?.payload || [];
  } catch {
    receiptAccounts.value = [];
  }
  settlementRef.value?.open();
};

// 水单等附件挂到订单上，走订单本来的附件接口（和订单详情里看到的是同一批）。
const uploadSettlementFiles = async () => {
  if (!settlementFiles.value.length) return;

  const fd = new FormData();
  settlementFiles.value.forEach(f => fd.append('files[]', f));
  await axios.post(
    `/api/v1/accounts/${accountId.value}/crm/sales_orders/${convertedOrder.id}/attach`,
    fd,
    { headers: { 'Content-Type': 'multipart/form-data' } }
  );
};

const saveSettlement = async () => {
  if (!convertedOrder.id || savingSettlement.value) return;
  savingSettlement.value = true;
  const payload = {
    payment_term: settlement.paymentTerm || null,
    delivery_method: settlement.deliveryMethod || null,
  };
  if (settlement.insuranceOrderNo.trim()) {
    payload.insurance_order_no = settlement.insuranceOrderNo.trim();
  }
  if (settlement.receiptAccountId) {
    payload.receipt_account_id = settlement.receiptAccountId;
  }
  try {
    await axios.patch(
      `/api/v1/accounts/${accountId.value}/crm/sales_orders/${convertedOrder.id}`,
      { sales_order: payload }
    );
    await uploadSettlementFiles();
    useAlert(`订单 ${convertedOrder.no} 的结算信息已补上`);
    settlementRef.value?.close();
    emit('saved');
  } catch (error) {
    useAlert(error?.response?.data?.message || '保存失败，可到销售订单里再补');
  } finally {
    savingSettlement.value = false;
  }
};

const submit = async () => {
  if (!isValid.value || saving.value) return;
  saving.value = true;
  try {
    const fd = buildFormData();
    let convertedOrderNo = null;
    let converted = null;
    if (editingId.value) {
      const { data } = await PisAPI.update(
        accountId.value,
        editingId.value,
        fd
      );
      convertedOrderNo = data?.converted_order_no;
      converted = data;
    } else {
      await PisAPI.create(accountId.value, fd);
    }
    useAlert(
      convertedOrderNo
        ? t('CRM.PI.FORM.SAVED_CONVERTED', { no: convertedOrderNo })
        : t('CRM.PI.FORM.SAVED')
    );
    markPristine();
    dialogRef.value?.close();
    emit('saved');
    // 刚转出来的单缺结算方式（或抬头没对上收款账户）就地补，别让它空着流到应收台账
    const missing = converted?.converted_order_missing || [];
    const needs =
      missing.includes('payment_term') ||
      missing.includes('receipt_account_id');
    if (converted?.converted_order_id && needs) {
      openSettlement({
        id: converted.converted_order_id,
        no: convertedOrderNo,
        missing,
      });
    }
  } catch (error) {
    // 后端 422 带着具体原因（最常见：PI 号重号），不透出来业务员只会看到一句「保存失败」。
    const detail = error?.response?.data?.message;
    useAlert(detail || t('CRM.PI.FORM.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

// 列表上一键标「已付款」：不用点进来改状态再保存一遍。
// 走和编辑保存同一条路（PUT /crm/pis/:id 只带 status），所以自动转销售订单、
// 转完补结算信息这两步照旧——逻辑收在这一处，列表页不重写一份。
const markingPaid = ref(false);
const markPaid = async record => {
  if (markingPaid.value) return false;
  markingPaid.value = true;
  try {
    const fd = new FormData();
    fd.append('pi[status]', 'PAID');
    const { data } = await PisAPI.update(accountId.value, record.id, fd);
    const no = data?.converted_order_no;
    useAlert(
      no ? t('CRM.PI.FORM.SAVED_CONVERTED', { no }) : t('CRM.PI.FORM.SAVED')
    );
    emit('saved');
    const missing = data?.converted_order_missing || [];
    if (
      data?.converted_order_id &&
      (missing.includes('payment_term') ||
        missing.includes('receipt_account_id'))
    ) {
      openSettlement({ id: data.converted_order_id, no, missing });
    }
    return true;
  } catch (error) {
    useAlert(error?.response?.data?.message || t('CRM.PI.FORM.SAVE_ERROR'));
    return false;
  } finally {
    markingPaid.value = false;
  }
};

defineExpose({ open, markPaid });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="4xl"
    overflow-y-auto
    confirm-button-color="iris"
    :dirty="isDirty"
    :title="
      editingId ? t('CRM.PI.FORM.EDIT_TITLE') : t('CRM.PI.FORM.NEW_TITLE')
    "
    :is-loading="saving"
    :disable-confirm-button="!isValid"
    @close="markPristine"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <!-- 上传 PI 自动识别（仅新建）：上传 PDF/Excel，自动填 PI号/日期/币种/客户/明细 -->
      <div v-if="!editingId" class="flex flex-col gap-1.5">
        <div
          class="crm-ai-box flex items-center justify-between gap-3 p-3 border border-dashed rounded-lg border-n-iris-6 bg-n-iris-2"
        >
          <div class="flex items-center gap-2 text-sm text-n-slate-11">
            {{ t('CRM.PI.PI.HINT') }}
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
            {{ parsingPi ? t('CRM.PI.PI.PARSING') : t('CRM.PI.PI.UPLOAD') }}
          </button>
          <input
            ref="piInputRef"
            type="file"
            accept=".pdf,.xlsx,.xls,.csv"
            class="hidden"
            @change="onPiSelected"
          />
        </div>
        <p v-if="piMatchHint" class="text-xs text-n-amber-11">
          {{ piMatchHint }}
        </p>
      </div>

      <!-- 基本 -->
      <div class="grid grid-cols-4 gap-3">
        <Input
          v-model="form.piNo"
          :label="t('CRM.PI.FORM.PI_NO')"
          :placeholder="t('CRM.PI.FORM.PI_NO_PLACEHOLDER')"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.DATE') }}
          </label>
          <DatePicker v-model="form.piDate" block />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.STATUS') }}
          </label>
          <SelectCard v-model="form.status" :options="statusOptions" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.CURRENCY') }}
          </label>
          <SelectCard v-model="form.currency" :options="currencyOptions" />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.CUSTOMER') }}
          </label>
          <ComboBox
            :model-value="form.crmCustomerId"
            :options="customerOptions"
            use-api-results
            :display-label="editingCustomerLabel"
            :placeholder="
              loadingCustomers
                ? t('CRM.PI.FORM.CUSTOMER_LOADING')
                : t('CRM.PI.FORM.CUSTOMER_PLACEHOLDER')
            "
            search-placeholder="搜客户名 / 联系人 / 邮箱"
            @open="onCustomerOpen"
            @search="onCustomerSearch"
            @update:model-value="onCustomerChange"
          />
        </div>

        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.COMPANY_HEADER') }}
          </label>
          <SelectCard
            v-model="form.companyHeader"
            :options="companyHeaderOptions"
          />
          <p class="text-xs text-n-slate-10">
            {{ t('CRM.PI.FORM.COMPANY_HEADER_HINT') }}
          </p>
        </div>
      </div>

      <!-- 买方 -->
      <div
        class="flex items-center gap-2 mt-1 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        {{ t('CRM.PI.FORM.SECTION_BUYER') }}
      </div>
      <div class="grid grid-cols-2 gap-3">
        <Input v-model="form.attention" :label="t('CRM.PI.FORM.ATTENTION')" />
        <Input v-model="form.buyerCompany" :label="t('CRM.PI.FORM.COMPANY')" />
      </div>
      <TextArea v-model="form.buyerAddress" :label="t('CRM.PI.FORM.ADDRESS')" />
      <div class="grid grid-cols-3 gap-3">
        <Input v-model="form.buyerEmail" :label="t('CRM.PI.FORM.EMAIL')" />
        <Input v-model="form.buyerTel" :label="t('CRM.PI.FORM.TEL')" />
        <Input v-model="form.buyerEori" :label="t('CRM.PI.FORM.EORI')" />
      </div>

      <!-- 装运 -->
      <div
        class="flex items-center gap-2 mt-1 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        {{ t('CRM.PI.FORM.SECTION_SHIP') }}
      </div>
      <div class="grid grid-cols-2 gap-3">
        <Input
          v-model="form.portOfShipment"
          :label="t('CRM.PI.FORM.PORT_SHIP')"
        />
        <Input
          v-model="form.portOfDestination"
          :label="t('CRM.PI.FORM.PORT_DEST')"
        />
        <Input
          v-model="form.countryOfOrigin"
          :label="t('CRM.PI.FORM.ORIGIN')"
        />
        <Input
          v-model="form.shippingMethod"
          :label="t('CRM.PI.FORM.SHIP_METHOD')"
        />
      </div>

      <!-- 明细 -->
      <div class="flex items-center justify-between mt-1">
        <span
          class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
        >
          <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
          {{ t('CRM.PI.FORM.SECTION_ITEMS') }}
        </span>
        <button
          type="button"
          class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          @click="addItem"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('CRM.PI.FORM.ADD_ITEM') }}
        </button>
      </div>
      <div v-if="!form.items.length" class="text-xs text-n-slate-10">
        {{ t('CRM.PI.FORM.ITEMS_EMPTY') }}
      </div>
      <div v-else class="flex flex-col gap-2">
        <div
          v-for="(it, i) in form.items"
          :key="i"
          class="flex items-start gap-2 p-2 border rounded-lg border-n-weak"
        >
          <!-- 序号：一张 PI 常有六七个型号，没有序号对不上客户回邮里说的「第 3 项」。 -->
          <span
            class="w-5 pt-1 text-xs text-right shrink-0 tabular-nums text-n-slate-10"
          >
            {{ i + 1 }}
          </span>
          <div class="flex flex-col items-center gap-1 shrink-0">
            <button
              type="button"
              class="flex items-center justify-center overflow-hidden border rounded-md size-14 border-n-weak bg-n-alpha-1 text-n-slate-10 hover:bg-n-alpha-2"
              :title="t('CRM.PI.FORM.ITEM_PIC')"
              @click="triggerItemPic(i)"
            >
              <img
                v-if="it.pictureUrl"
                :src="it.pictureUrl"
                class="object-contain size-full"
              />
              <span v-else class="i-lucide-image-plus size-5" />
            </button>
            <button
              type="button"
              class="flex items-center gap-0.5 text-[11px] text-n-slate-10 hover:text-n-slate-12"
              title="从知识库选图"
              @click="openPicker(i)"
            >
              <span class="i-lucide-folder-open size-3 shrink-0" />
              知识库
            </button>
            <input
              :ref="el => (itemPicInputs[i] = el)"
              type="file"
              accept="image/*"
              class="hidden"
              @change="e => onItemPic(e, i)"
            />
          </div>
          <div class="flex flex-col flex-1 min-w-0 gap-2">
            <div class="flex gap-2">
              <Input
                v-model="it.model"
                class="w-40 shrink-0"
                :placeholder="t('CRM.PI.FORM.ITEM_MODEL')"
              />
              <Input
                v-model="it.description"
                class="flex-1"
                :placeholder="t('CRM.PI.FORM.ITEM_DESC')"
              />
            </div>
            <div class="flex items-center gap-2">
              <Input
                v-model="it.quantity"
                type="number"
                class="w-24"
                :placeholder="t('CRM.PI.FORM.ITEM_QTY')"
              />
              <Input
                v-model="it.unitPrice"
                type="number"
                class="w-32"
                :placeholder="t('CRM.PI.FORM.ITEM_PRICE')"
              />
              <span
                class="flex-1 text-sm text-right text-n-slate-11 tabular-nums"
              >
                {{ fmtAmount(rowAmount(it)) }}
              </span>
              <button
                type="button"
                class="flex items-center justify-center size-8 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                :title="t('CRM.PI.FORM.ITEM_REMOVE')"
                @click="removeItem(i)"
              >
                <span class="i-lucide-x size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- 费用 -->
      <div class="grid grid-cols-2 gap-3">
        <Input
          v-model="form.shippingCostLabel"
          :label="t('CRM.PI.FORM.SHIP_COST_LABEL')"
        />
        <Input
          v-model="form.shippingCost"
          type="number"
          :label="t('CRM.PI.FORM.SHIP_COST')"
        />
      </div>
      <div class="flex items-center justify-end gap-3 px-1">
        <span class="text-sm text-n-slate-11">
          {{ t('CRM.PI.FORM.GRAND_TOTAL') }}
        </span>
        <span class="text-base font-semibold text-n-slate-12 tabular-nums">
          {{ fmtAmount(grandTotal) }}
        </span>
      </div>

      <!-- 条款（自适应高度，写多少显示多少，不用滚动） -->
      <TextArea
        v-model="form.terms"
        :label="t('CRM.PI.FORM.TERMS')"
        auto-height
        resize
      />

      <!-- 卖方落款（按业务员预录带入，可当次改） -->
      <div
        class="flex items-center gap-2 mt-1 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        {{ t('CRM.PI.FORM.SECTION_SELLER') }}
      </div>
      <p class="-mt-2 text-xs text-n-slate-10">
        {{ t('CRM.PI.FORM.SELLER_HINT') }}
      </p>
      <div class="grid grid-cols-3 gap-3">
        <Input v-model="form.issuedBy" :label="t('CRM.PI.FORM.ISSUED_BY')" />
        <Input
          v-model="form.sellerMobile"
          :label="t('CRM.PI.FORM.SELLER_MOBILE')"
        />
        <Input
          v-model="form.sellerEmail"
          :label="t('CRM.PI.FORM.SELLER_EMAIL')"
        />
      </div>
      <TextArea
        v-model="form.remark"
        :label="t('CRM.PI.FORM.REMARK')"
        auto-height
        resize
      />
    </div>
  </Dialog>
  <!-- 转单后补填结算信息：PI 不录这几项（要发给客户），转成销售订单那一刻就地补 -->
  <Dialog
    ref="settlementRef"
    :title="`补全结算信息 · ${convertedOrder.no}`"
    confirm-button-label="保存"
    cancel-button-label="稍后再补"
    :is-loading="savingSettlement"
    :disable-confirm-button="isSettlementInvalid"
    @confirm="saveSettlement"
  >
    <div class="flex flex-col gap-4">
      <p class="text-sm text-n-slate-11">
        这张 PI 已付款并转成销售订单
        <span class="font-medium text-n-slate-12">{{ convertedOrder.no }}</span>
        。结算方式是转 ERP 销售订单的必填项。
      </p>
      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            结算方式
            <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="settlement.paymentTerm"
            :options="paymentTermOptions"
          />
        </div>
        <div
          v-if="convertedOrder.missing.includes('receipt_account_id')"
          class="flex flex-col min-w-0 gap-1"
        >
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            收款账户
            <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="settlement.receiptAccountId"
            :options="receiptAccountOptions"
          />
        </div>
        <div v-else class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            收款账户
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm rounded-lg bg-n-slate-3 text-n-slate-11"
          >
            已按 PI 抬头带入
          </div>
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            交货方式
            <span class="text-n-ruby-11">*</span>
          </label>
          <SelectCard
            v-model="settlement.deliveryMethod"
            :options="DELIVERY_METHOD_OPTIONS"
          />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            信保订单号
          </label>
          <Input v-model="settlement.insuranceOrderNo" />
        </div>
        <!-- 收款水单这类单据：挂到订单附件上，和订单详情里看到的是同一批 -->
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">附件</label>
          <Button
            label="添加附件"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-paperclip"
            class="self-start !h-10"
            @click="pickSettlementFiles"
          />
          <input
            ref="settlementFileRef"
            type="file"
            multiple
            class="hidden"
            @change="onSettlementFiles"
          />
          <span v-if="!settlementFiles.length" class="text-xs text-n-slate-11">
            收款水单、银行回单等
          </span>
          <div v-else class="flex flex-col gap-1 mt-1">
            <span
              v-for="(f, i) in settlementFiles"
              :key="`${f.name}-${i}`"
              class="inline-flex items-center gap-2 text-xs text-n-slate-11"
            >
              <span class="truncate">{{ f.name }}</span>
              <button
                type="button"
                class="shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                @click="removeSettlementFile(i)"
              >
                ✕
              </button>
            </span>
          </div>
        </div>
      </div>
    </div>
  </Dialog>
  <CrmKnowledgeImagePicker ref="pickerRef" @pick="onPickFromLibrary" />
</template>
