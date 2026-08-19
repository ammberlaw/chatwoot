<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import QuotesAPI from 'dashboard/api/crm/quotes';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);

const { accountId } = useAccount();
const dialogRef = ref(null);
const editingId = ref(null);
const quoteNo = ref('');
const saving = ref(false);

// 关联客户下拉：一次拉全（per_page=200）。
const customers = ref([]); // [{ id, name }]
const loadingCustomers = ref(false);
const editingCustomer = ref(null); // 编辑态原客户（可能不在下拉列表，兜底显示）

const today = () => new Date().toISOString().slice(0, 10);

const blankLineItem = () => ({
  id: null,
  name: '',
  spec: '',
  quantity: '',
  unitPrice: '',
  picturePreview: '',
  pictureFile: null,
});

// 编辑态被删除的既有明细 id（提交时带 _destroy 通知后端删除）。
const removedIds = ref([]);

const form = reactive({
  name: '',
  crmCustomerId: '',
  status: 'DRAFT',
  quoteCurrency: 'USD',
  quoteDate: today(),
  validUntil: '',
  discount: '',
  shipping: '',
  tax: '',
  remark: '',
  lineItems: [blankLineItem()],
});

const statusOptions = [
  { value: 'DRAFT', label: '草稿' },
  { value: 'SENT', label: '已发送' },
  { value: 'CONFIRMED', label: '已确认' },
  { value: 'EXPIRED', label: '已过期' },
];

const currencyOptions = [
  { value: 'USD', label: 'US$ USD' },
  { value: 'CNY', label: '¥ CNY' },
  { value: 'EUR', label: '€ EUR' },
];

const CURRENCY_SYMBOL = { USD: 'US$', CNY: '¥', EUR: '€' };

const isEditing = computed(() => editingId.value !== null);

const customerOptions = computed(() =>
  customers.value.map(c => ({ value: String(c.id), label: c.name }))
);

// 编辑态原客户若不在下拉（换负责人/转公海），用 displayLabel 兜底避免空白。
const customerDisplayLabel = computed(() => {
  if (!editingCustomer.value) return '';
  const id = String(editingCustomer.value.id);
  if (customerOptions.value.some(o => o.value === id)) return '';
  return editingCustomer.value.name;
});

// 数字解析：空串/非法 → 0。
const num = v => {
  if (v === '' || v === null || v === undefined) return 0;
  const n = parseFloat(v);
  return Number.isNaN(n) ? 0 : n;
};

const toMicros = v => Math.round(num(v) * 1_000_000);

const fmtMoney = value =>
  `${CURRENCY_SYMBOL[form.quoteCurrency] || ''}${value.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

// 明细金额（实时）= 数量 × 单价。
const lineAmount = li => num(li.quantity) * num(li.unitPrice);

const subtotal = computed(() =>
  form.lineItems.reduce((sum, li) => sum + lineAmount(li), 0)
);
const total = computed(
  () => subtotal.value - num(form.discount) + num(form.shipping) + num(form.tax)
);

const addLineItem = () => form.lineItems.push(blankLineItem());
const removeLineItem = index => {
  const [removed] = form.lineItems.splice(index, 1);
  if (removed?.id) removedIds.value.push(removed.id);
  if (!form.lineItems.length) form.lineItems.push(blankLineItem());
};

// 每行产品图上传/预览（本地 blob 预览，提交时随明细上传 File）。
const linePicInputs = ref({});
const triggerLinePic = index => linePicInputs.value[index]?.click();
const onLinePic = (event, index) => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  form.lineItems[index].pictureFile = file;
  form.lineItems[index].picturePreview = URL.createObjectURL(file);
};
const clearLinePic = index => {
  form.lineItems[index].pictureFile = null;
  form.lineItems[index].picturePreview = '';
};

const isFormInvalid = computed(
  () => !form.name.trim() || !form.lineItems.some(li => (li.name || '').trim())
);

const resetForm = () => {
  editingId.value = null;
  quoteNo.value = '';
  editingCustomer.value = null;
  form.name = '';
  form.crmCustomerId = '';
  form.status = 'DRAFT';
  form.quoteCurrency = 'USD';
  form.quoteDate = today();
  form.validUntil = '';
  form.discount = '';
  form.shipping = '';
  form.tax = '';
  form.remark = '';
  form.lineItems = [blankLineItem()];
  removedIds.value = [];
};

const loadCustomers = async () => {
  loadingCustomers.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { filter: 'mine_shared', per_page: 200 } }
    );
    customers.value = (data.payload || []).map(c => ({
      id: c.id,
      name: c.name,
    }));
  } catch {
    customers.value = [];
  } finally {
    loadingCustomers.value = false;
  }
};

// 选中客户后带出币种，并在名称为空时预填「报价单-客户名」。
const onCustomerChange = async () => {
  if (!form.crmCustomerId) return;
  try {
    const { data } = await QuotesAPI.prefill(
      accountId.value,
      form.crmCustomerId
    );
    if (data.quote_currency) form.quoteCurrency = data.quote_currency;
    if (!form.name.trim()) {
      const picked = customers.value.find(
        c => String(c.id) === String(form.crmCustomerId)
      );
      const custName = data.customer_name || picked?.name || '';
      if (custName) form.name = `报价单-${custName}`;
    }
  } catch {
    // 带出失败不阻塞录入。
  }
};

const open = record => {
  resetForm();
  if (record) {
    editingId.value = record.id;
    quoteNo.value = record.quoteNo || '';
    editingCustomer.value = record.crmCustomerId
      ? { id: record.crmCustomerId, name: record.customerName || '客户' }
      : null;
    form.name = record.name || '';
    form.crmCustomerId = record.crmCustomerId
      ? String(record.crmCustomerId)
      : '';
    form.status = record.status || 'DRAFT';
    form.quoteCurrency = record.quoteCurrency || 'USD';
    form.quoteDate = record.quoteDate ? record.quoteDate.slice(0, 10) : today();
    form.validUntil = record.validUntil ? record.validUntil.slice(0, 10) : '';
    form.discount = record.discountAmountMicros
      ? String(record.discountAmountMicros / 1_000_000)
      : '';
    form.shipping = record.shippingFeeMicros
      ? String(record.shippingFeeMicros / 1_000_000)
      : '';
    form.tax = record.taxAmountMicros
      ? String(record.taxAmountMicros / 1_000_000)
      : '';
    form.remark = record.remark || '';
    form.lineItems =
      Array.isArray(record.lineItems) && record.lineItems.length
        ? record.lineItems.map(li => ({
            id: li.id,
            name: li.name || li.productNameSnapshot || '',
            spec: li.specSnapshot || '',
            quantity: li.quantity ?? '',
            unitPrice:
              li.unitPriceMicros != null
                ? String(li.unitPriceMicros / 1_000_000)
                : '',
            picturePreview: li.pictureUrl || '',
            pictureFile: null,
          }))
        : [blankLineItem()];
  }
  loadCustomers();
  dialogRef.value?.open();
};

const buildFormData = () => {
  const fd = new FormData();
  fd.append('quote[name]', form.name.trim());
  fd.append('quote[status]', form.status);
  if (form.crmCustomerId) {
    fd.append('quote[crm_customer_id]', form.crmCustomerId);
  }
  fd.append('quote[quote_date]', form.quoteDate || '');
  fd.append('quote[valid_until]', form.validUntil || '');
  fd.append('quote[quote_currency]', form.quoteCurrency);
  fd.append('quote[discount_amount_micros]', toMicros(form.discount));
  fd.append('quote[shipping_fee_micros]', toMicros(form.shipping));
  fd.append('quote[tax_amount_micros]', toMicros(form.tax));
  fd.append('quote[remark]', form.remark.trim());

  // 保留行（跳过无名行）：Rails 嵌套属性约定，索引连续。
  const keptRows = form.lineItems.filter(li => (li.name || '').trim());
  keptRows.forEach((li, i) => {
    const p = `quote[line_items_attributes][${i}]`;
    if (li.id) fd.append(`${p}[id]`, li.id);
    fd.append(`${p}[name]`, li.name.trim());
    fd.append(`${p}[spec_snapshot]`, (li.spec || '').trim());
    fd.append(`${p}[quantity]`, li.quantity || 0);
    fd.append(`${p}[unit_price_micros]`, toMicros(li.unitPrice));
    if (li.pictureFile) fd.append(`${p}[picture]`, li.pictureFile);
  });

  // 删除的既有行：索引接着保留行往后排，避免撞键。
  removedIds.value.forEach((removedId, offset) => {
    const p = `quote[line_items_attributes][${keptRows.length + offset}]`;
    fd.append(`${p}[id]`, removedId);
    fd.append(`${p}[_destroy]`, '1');
  });

  return fd;
};

const handleConfirm = async () => {
  if (isFormInvalid.value || saving.value) return;

  const fd = buildFormData();

  saving.value = true;
  try {
    if (isEditing.value) {
      await QuotesAPI.update(accountId.value, editingId.value, fd);
      useAlert('报价已更新');
    } else {
      await QuotesAPI.create(accountId.value, fd);
      useAlert('报价已创建');
    }
    emit('saved');
    resetForm();
    dialogRef.value?.close();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败，请重试');
  } finally {
    saving.value = false;
  }
};

defineExpose({ dialogRef, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    confirm-button-color="iris"
    :title="isEditing ? '编辑报价' : '新建报价'"
    description="填写报价基本信息与明细，合计将自动计算。"
    :is-loading="isLoading || saving"
    :disable-confirm-button="isFormInvalid"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <!-- 基本信息 -->
      <div
        class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
        基本信息
      </div>
      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            报价名称
            <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="form.name" autofocus />
        </div>
        <div v-if="isEditing" class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            报价单号
          </label>
          <div
            class="flex items-center h-10 px-3 text-sm rounded-lg bg-n-slate-3 text-n-slate-11"
          >
            {{ quoteNo }}
          </div>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            关联客户
          </label>
          <ComboBox
            v-model="form.crmCustomerId"
            :options="customerOptions"
            :display-label="customerDisplayLabel"
            :placeholder="loadingCustomers ? '加载中…' : '选择客户'"
            search-placeholder="搜索客户"
            empty-state="无匹配客户"
            @update:model-value="onCustomerChange"
          />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12"> 状态 </label>
          <SelectCard v-model="form.status" :options="statusOptions" />
        </div>
      </div>

      <div class="grid grid-cols-3 gap-4">
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12"> 币种 </label>
          <SelectCard v-model="form.quoteCurrency" :options="currencyOptions" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            报价日期
          </label>
          <DatePicker v-model="form.quoteDate" block />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12"> 有效期 </label>
          <DatePicker v-model="form.validUntil" block />
        </div>
      </div>

      <TextArea v-model="form.remark" label="备注" :max-length="2000" />

      <!-- 报价明细 -->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span
            class="flex items-center gap-2 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
          >
            <span class="w-1 rounded-full h-3.5 bg-n-iris-9" />
            报价明细
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="addLineItem"
          >
            <span class="i-lucide-plus size-4" />
            添加明细
          </button>
        </div>

        <div class="flex flex-col gap-1.5">
          <div class="flex gap-2 px-1 text-xs font-medium text-n-slate-10">
            <span class="w-10 shrink-0">图片</span>
            <span class="flex-[3]">产品/名称</span>
            <span class="flex-[2]">规格</span>
            <span class="flex-1">数量</span>
            <span class="flex-1">单价</span>
            <span class="flex-1 text-right">金额</span>
            <span class="w-6 shrink-0" />
          </div>
          <div
            v-for="(li, index) in form.lineItems"
            :key="index"
            class="flex items-center gap-2"
          >
            <div class="relative w-10 shrink-0">
              <template v-if="li.picturePreview">
                <img
                  :src="li.picturePreview"
                  class="object-contain border rounded-md size-10 border-n-weak bg-n-alpha-1"
                  alt=""
                />
                <button
                  type="button"
                  class="absolute flex items-center justify-center text-white rounded-full -right-1.5 -top-1.5 size-4 bg-n-slate-11 hover:bg-n-ruby-11"
                  title="清除图片"
                  @click="clearLinePic(index)"
                >
                  <span class="i-lucide-x size-3" />
                </button>
              </template>
              <button
                v-else
                type="button"
                class="flex items-center justify-center gap-0.5 text-[11px] border border-dashed rounded-md size-10 border-n-weak text-n-slate-10 hover:bg-n-alpha-1"
                title="上传图片"
                @click="triggerLinePic(index)"
              >
                <span class="i-lucide-image-plus size-4" />
              </button>
              <input
                :ref="el => (linePicInputs[index] = el)"
                type="file"
                accept="image/*"
                class="hidden"
                @change="e => onLinePic(e, index)"
              />
            </div>
            <Input v-model="li.name" class="flex-[3]" />
            <Input v-model="li.spec" class="flex-[2]" />
            <Input v-model="li.quantity" type="number" class="flex-1" />
            <Input v-model="li.unitPrice" type="number" class="flex-1" />
            <span
              class="flex-1 text-right text-[13px] font-medium tabular-nums text-n-slate-12"
            >
              {{ fmtMoney(lineAmount(li)) }}
            </span>
            <button
              type="button"
              class="flex items-center justify-center w-6 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
              title="删除"
              @click="removeLineItem(index)"
            >
              <span class="i-lucide-x size-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- 金额合计 -->
      <div
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1/60"
      >
        <div class="flex items-center justify-between text-sm text-n-slate-11">
          <span>小计</span>
          <span class="font-medium tabular-nums text-n-slate-12">
            {{ fmtMoney(subtotal) }}
          </span>
        </div>
        <div class="grid grid-cols-3 gap-3">
          <Input v-model="form.discount" type="number" label="折扣" />
          <Input v-model="form.shipping" type="number" label="运费" />
          <Input v-model="form.tax" type="number" label="税费" />
        </div>
        <div
          class="flex items-center justify-between pt-2 mt-1 border-t border-n-weak"
        >
          <span class="text-sm font-semibold text-n-slate-12">合计</span>
          <span class="text-[20px] font-bold tabular-nums text-n-iris-11">
            {{ fmtMoney(total) }}
          </span>
        </div>
      </div>
    </div>
  </Dialog>
</template>
