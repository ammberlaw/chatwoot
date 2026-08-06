<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmOpportunitiesStore } from 'dashboard/stores/crm/opportunities';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
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

// 关联私海客户：仅当前业务员名下（filter=mine）的客户，用于把订单归到该客户名下统计成交额。
const privateCustomers = ref([]); // [{ id, name }]
const loadingCustomers = ref(false);
const editingCustomer = ref(null); // 编辑态原关联客户（可能已不在私海，需保留可选）

// 附件：新建时选中的文件暂存内存（pendingFiles），随创建请求一起 multipart 提交；
// 编辑时对已存在订单即时 attach/detach。
const fileInputRef = ref(null);
const pendingFiles = ref([]); // File[]（新建模式）
const attachments = ref([]); // 已保存附件（编辑模式）
const uploading = ref(false);

const today = () => new Date().toISOString().slice(0, 10);

const form = reactive({
  name: '',
  piNo: '',
  crmCustomerId: '',
  crmOpportunityId: '',
  status: 'IN_PRODUCTION',
  orderDate: today(),
  deliveryDate: '',
  amount: '',
  orderCurrency: 'CNY',
  exchangeRate: '',
  remark: '',
  lineItems: [], // [{ name, spec, quantity, unitPrice, amount }]
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
  form.lineItems = Array.isArray(data.line_items)
    ? data.line_items.map(li => ({
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

  pendingFiles.value = [...pendingFiles.value, file];
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

const addLineItem = () =>
  form.lineItems.push({
    name: '',
    spec: '',
    quantity: '',
    unitPrice: '',
    amount: '',
  });
const removeLineItem = index => form.lineItems.splice(index, 1);

// 上传的订单均为已付款订单，无「待确认」环节，默认从「生产中」起。
const statusOptions = [
  { value: 'IN_PRODUCTION', label: '生产中' },
  { value: 'PENDING_SHIPMENT', label: '待出货' },
  { value: 'SHIPPED', label: '已出货' },
  { value: 'COMPLETED', label: '已完成' },
  { value: 'CANCELLED', label: '已取消' },
];

const currencyOptions = ['CNY', 'USD', 'EUR'].map(v => ({
  value: v,
  label: v,
}));

const customerOptions = computed(() =>
  privateCustomers.value.map(c => ({ value: String(c.id), label: c.name }))
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

const isEditing = computed(() => editingId.value !== null);
// 新建订单：附件必填（如 PI、生产订单），否则不可保存。
const isFormInvalid = computed(
  () =>
    !form.name.trim() ||
    !form.orderDate ||
    (!isEditing.value && pendingFiles.value.length === 0)
);

const resetForm = () => {
  editingId.value = null;
  orderNo.value = '';
  editingCustomer.value = null;
  pendingFiles.value = [];
  attachments.value = [];
  piMatchHint.value = '';
  form.name = '';
  form.piNo = '';
  form.crmCustomerId = '';
  form.crmOpportunityId = '';
  form.status = 'IN_PRODUCTION';
  form.orderDate = today();
  form.deliveryDate = '';
  form.amount = '';
  form.orderCurrency = 'CNY';
  form.exchangeRate = '';
  form.remark = '';
  form.lineItems = [];
};

// 拉取当前业务员名下私海客户（一次拿全）。
const loadPrivateCustomers = async () => {
  loadingCustomers.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { filter: 'mine', per_page: 200 } }
    );
    privateCustomers.value = (data.payload || []).map(c => ({
      id: c.id,
      name: c.name,
    }));
  } catch {
    privateCustomers.value = [];
  } finally {
    loadingCustomers.value = false;
  }
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
          name: li.name || '',
          spec: li.spec || '',
          quantity: li.quantity ?? '',
          unitPrice: li.unitPrice ?? '',
          amount: li.amount ?? '',
        }))
      : [];
    form.crmCustomerId = record.crmCustomerId
      ? String(record.crmCustomerId)
      : '';
    form.crmOpportunityId = record.crmOpportunityId
      ? String(record.crmOpportunityId)
      : '';
    form.status = record.status || 'IN_PRODUCTION';
    form.orderDate = record.orderDate ? record.orderDate.slice(0, 10) : today();
    form.deliveryDate = record.deliveryDate
      ? record.deliveryDate.slice(0, 10)
      : '';
    form.amount = record.orderAmountMicros
      ? String(record.orderAmountMicros / 1_000_000)
      : '';
    form.orderCurrency = record.orderCurrency || 'CNY';
    form.exchangeRate =
      record.exchangeRate != null ? String(record.exchangeRate) : '';
    form.remark = record.remark || '';
  }
  loadPrivateCustomers();
  if (!opportunitiesStore.getRecords.length) {
    opportunitiesStore.get({ page: 1, perPage: 100 });
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
    crmCustomerId: form.crmCustomerId || null,
    crmOpportunityId: form.crmOpportunityId || null,
    status: form.status,
    orderDate: form.orderDate,
    deliveryDate: form.deliveryDate || null,
    orderAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    orderCurrency: form.orderCurrency,
    exchangeRate: form.exchangeRate ? parseFloat(form.exchangeRate) : null,
    remark: form.remark.trim() || null,
    lineItemsJson: JSON.stringify(lineItemsPayload),
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', { ...payload, __files: pendingFiles.value });
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

defineExpose({ dialogRef, onSuccess, open });
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
        class="flex items-center justify-between gap-3 p-3 border border-dashed rounded-lg border-n-iris-6 bg-n-iris-2"
      >
        <div class="flex items-center gap-2 text-sm text-n-slate-11">
          <span class="i-lucide-sparkles size-4 text-n-iris-9" />
          {{ t('CRM.SALES_ORDERS.PI.HINT') }}
        </div>
        <button
          type="button"
          class="flex items-center gap-1.5 h-8 px-3 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
          :disabled="parsingPi"
          @click="triggerPiUpload"
        >
          <span
            class="size-4"
            :class="
              parsingPi
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-sparkles'
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
          accept=".pdf,.xlsx,.csv"
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
        <div class="flex flex-col min-w-0 gap-1">
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
          <Select
            v-model="form.crmOpportunityId"
            :options="opportunityOptions"
          />
        </div>
      </div>

      <div class="grid grid-cols-3 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.STATUS') }}
          </label>
          <Select v-model="form.status" :options="statusOptions" />
        </div>
        <Input
          v-model="form.orderDate"
          type="date"
          :label="t('CRM.SALES_ORDERS.FORM.ORDER_DATE')"
        />
        <Input
          v-model="form.deliveryDate"
          type="date"
          :label="t('CRM.SALES_ORDERS.FORM.DELIVERY_DATE')"
        />
      </div>

      <div
        class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        {{ t('CRM.SALES_ORDERS.FORM.SECTION_AMOUNT') }}
      </div>
      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.AMOUNT')"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.SALES_ORDERS.FORM.CURRENCY') }}
          </label>
          <Select v-model="form.orderCurrency" :options="currencyOptions" />
        </div>
        <Input
          v-model="form.exchangeRate"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.EXCHANGE_RATE')"
        />
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

        <div v-if="!form.lineItems.length" class="text-xs text-n-slate-10">
          {{ t('CRM.SALES_ORDERS.ITEMS.EMPTY') }}
        </div>
        <div v-else class="flex flex-col gap-1.5">
          <div class="flex gap-2 px-1 text-xs font-medium text-n-slate-10">
            <span class="flex-[3]">{{ t('CRM.SALES_ORDERS.ITEMS.NAME') }}</span>
            <span class="flex-[2]">{{ t('CRM.SALES_ORDERS.ITEMS.SPEC') }}</span>
            <span class="flex-1">{{ t('CRM.SALES_ORDERS.ITEMS.QTY') }}</span>
            <span class="flex-1">{{ t('CRM.SALES_ORDERS.ITEMS.PRICE') }}</span>
            <span class="flex-1">{{ t('CRM.SALES_ORDERS.ITEMS.AMOUNT') }}</span>
            <span class="w-6 shrink-0" />
          </div>
          <div
            v-for="(li, index) in form.lineItems"
            :key="index"
            class="flex items-center gap-2"
          >
            <Input v-model="li.name" class="flex-[3]" />
            <Input v-model="li.spec" class="flex-[2]" />
            <Input v-model="li.quantity" type="number" class="flex-1" />
            <Input v-model="li.unitPrice" type="number" class="flex-1" />
            <Input v-model="li.amount" type="number" class="flex-1" />
            <button
              type="button"
              class="flex items-center justify-center w-6 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
              :title="t('CRM.SALES_ORDERS.ITEMS.REMOVE')"
              @click="removeLineItem(index)"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
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
          v-if="!isEditing && pendingFiles.length === 0"
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
