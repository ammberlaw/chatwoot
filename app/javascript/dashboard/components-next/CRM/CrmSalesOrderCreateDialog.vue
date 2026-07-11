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
  crmCustomerId: '',
  crmOpportunityId: '',
  status: 'PENDING_CONFIRMATION',
  orderDate: today(),
  deliveryDate: '',
  amount: '',
  cost: '',
  orderCurrency: 'CNY',
  exchangeRate: '',
  remark: '',
});

const statusOptions = [
  { value: 'PENDING_CONFIRMATION', label: '待确认' },
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
    ? records.filter(o => String(o.crmCustomerId) === String(form.crmCustomerId))
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
  form.name = '';
  form.crmCustomerId = '';
  form.crmOpportunityId = '';
  form.status = 'PENDING_CONFIRMATION';
  form.orderDate = today();
  form.deliveryDate = '';
  form.amount = '';
  form.cost = '';
  form.orderCurrency = 'CNY';
  form.exchangeRate = '';
  form.remark = '';
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
    form.crmCustomerId = record.crmCustomerId ? String(record.crmCustomerId) : '';
    form.crmOpportunityId = record.crmOpportunityId ? String(record.crmOpportunityId) : '';
    form.status = record.status || 'PENDING_CONFIRMATION';
    form.orderDate = record.orderDate ? record.orderDate.slice(0, 10) : today();
    form.deliveryDate = record.deliveryDate ? record.deliveryDate.slice(0, 10) : '';
    form.amount = record.orderAmountMicros ? String(record.orderAmountMicros / 1_000_000) : '';
    form.cost = record.costAmountMicros ? String(record.costAmountMicros / 1_000_000) : '';
    form.orderCurrency = record.orderCurrency || 'CNY';
    form.exchangeRate = record.exchangeRate != null ? String(record.exchangeRate) : '';
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

  const payload = {
    name: form.name.trim(),
    crmCustomerId: form.crmCustomerId || null,
    crmOpportunityId: form.crmOpportunityId || null,
    status: form.status,
    orderDate: form.orderDate,
    deliveryDate: form.deliveryDate || null,
    orderAmountMicros: form.amount
      ? Math.round(parseFloat(form.amount) * 1_000_000)
      : null,
    costAmountMicros: form.cost
      ? Math.round(parseFloat(form.cost) * 1_000_000)
      : null,
    orderCurrency: form.orderCurrency,
    exchangeRate: form.exchangeRate ? parseFloat(form.exchangeRate) : null,
    remark: form.remark.trim() || null,
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
    :title="isEditing ? t('CRM.SALES_ORDERS.EDIT.TITLE') : t('CRM.SALES_ORDERS.CREATE.TITLE')"
    :description="t('CRM.SALES_ORDERS.CREATE.DESCRIPTION')"
    :is-loading="isLoading"
    :disable-confirm-button="isFormInvalid"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.name"
          :label="t('CRM.SALES_ORDERS.FORM.NAME')"
          autofocus
        />
        <div v-if="isEditing" class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
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
        <ComboBox
          v-model="form.crmCustomerId"
          :options="customerOptions"
          :display-label="customerDisplayLabel"
          :placeholder="loadingCustomers ? t('CRM.SALES_ORDERS.FORM.CUSTOMER_LOADING') : t('CRM.SALES_ORDERS.FORM.CUSTOMER_PLACEHOLDER')"
          :search-placeholder="t('CRM.SALES_ORDERS.FORM.CUSTOMER_SEARCH')"
          :empty-state="t('CRM.SALES_ORDERS.FORM.CUSTOMER_EMPTY')"
        />
        <Select
          v-model="form.crmOpportunityId"
          :label="t('CRM.SALES_ORDERS.FORM.OPPORTUNITY')"
          :options="opportunityOptions"
        />
      </div>

      <div class="grid grid-cols-3 gap-4">
        <Select
          v-model="form.status"
          :label="t('CRM.SALES_ORDERS.FORM.STATUS')"
          :options="statusOptions"
        />
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

      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.amount"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.AMOUNT')"
        />
        <Input
          v-model="form.cost"
          type="number"
          :label="t('CRM.SALES_ORDERS.FORM.COST')"
        />
        <Select
          v-model="form.orderCurrency"
          :label="t('CRM.SALES_ORDERS.FORM.CURRENCY')"
          :options="currencyOptions"
        />
      </div>

      <div class="grid grid-cols-3 gap-4">
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

      <!-- 附件（新建必填：PI / 生产订单）-->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
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
            {{ uploading ? t('CRM.SALES_ORDERS.ATTACH.UPLOADING') : t('CRM.SALES_ORDERS.ATTACH.ADD') }}
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
            <span class="text-xs text-n-slate-10">{{ prettySize(file.size) }}</span>
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
            <span class="text-xs text-n-slate-10">{{ prettySize(file.byte_size) }}</span>
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
