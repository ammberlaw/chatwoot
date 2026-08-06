<script setup>
/* global axios */
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import PisAPI from 'dashboard/api/crm/pis';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

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
  shippingCostLabel: 'SHIPPING COST (UPS)',
  shippingCost: '',
  terms: DEFAULT_TERMS,
  issuedBy: '',
  remark: '',
  items: [],
});

const form = reactive(blankForm());

const statusOptions = [
  { value: 'DRAFT', label: t('CRM.PI.STATUS.DRAFT') },
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
  customers.value.map(c => ({ value: String(c.id), label: c.name }))
);
const loadCustomers = async () => {
  loadingCustomers.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/customers`,
      { params: { filter: 'mine', per_page: 200 } }
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
  });
const removeItem = i => form.items.splice(i, 1);

const itemPicInputs = ref({});
const triggerItemPic = i => itemPicInputs.value[i]?.click();
const onItemPic = (event, i) => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  form.items[i].pictureFile = file;
  form.items[i].pictureUrl = URL.createObjectURL(file);
};

const reset = () => {
  editingId.value = null;
  editingCustomerLabel.value = '';
  Object.assign(form, blankForm());
  form.issuedBy = currentUser.value?.name || '';
};

const open = record => {
  reset();
  loadCustomers();
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
    }));
  }
  dialogRef.value?.open();
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
  set('remark', form.remark);

  form.items.forEach((it, i) => {
    const p = `pi[pi_items_attributes][${i}]`;
    if (it.id) fd.append(`${p}[id]`, it.id);
    fd.append(`${p}[position]`, i);
    fd.append(`${p}[model]`, it.model || '');
    fd.append(`${p}[description]`, it.description || '');
    fd.append(`${p}[quantity]`, num(it.quantity) ?? '');
    fd.append(`${p}[unit_price_micros]`, toMicros(it.unitPrice));
    if (it.pictureFile) fd.append(`${p}[picture]`, it.pictureFile);
  });
  return fd;
};

const submit = async () => {
  if (!isValid.value || saving.value) return;
  saving.value = true;
  try {
    const fd = buildFormData();
    if (editingId.value) {
      await PisAPI.update(accountId.value, editingId.value, fd);
    } else {
      await PisAPI.create(accountId.value, fd);
    }
    useAlert(t('CRM.PI.FORM.SAVED'));
    dialogRef.value?.close();
    emit('saved');
  } catch {
    useAlert(t('CRM.PI.FORM.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="4xl"
    overflow-y-auto
    confirm-button-color="iris"
    :title="
      editingId ? t('CRM.PI.FORM.EDIT_TITLE') : t('CRM.PI.FORM.NEW_TITLE')
    "
    :is-loading="saving"
    :disable-confirm-button="!isValid"
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <!-- 基本 -->
      <div class="grid grid-cols-4 gap-3">
        <Input
          v-model="form.piNo"
          :label="t('CRM.PI.FORM.PI_NO')"
          :placeholder="t('CRM.PI.FORM.PI_NO_PLACEHOLDER')"
        />
        <Input
          v-model="form.piDate"
          type="date"
          :label="t('CRM.PI.FORM.DATE')"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.STATUS') }}
          </label>
          <Select v-model="form.status" :options="statusOptions" />
        </div>
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('CRM.PI.FORM.CURRENCY') }}
          </label>
          <Select v-model="form.currency" :options="currencyOptions" />
        </div>
      </div>

      <div class="flex flex-col min-w-0 gap-1">
        <label class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('CRM.PI.FORM.CUSTOMER') }}
        </label>
        <ComboBox
          :model-value="form.crmCustomerId"
          :options="customerOptions"
          :display-label="editingCustomerLabel"
          :placeholder="
            loadingCustomers
              ? t('CRM.PI.FORM.CUSTOMER_LOADING')
              : t('CRM.PI.FORM.CUSTOMER_PLACEHOLDER')
          "
          @update:model-value="onCustomerChange"
        />
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

      <!-- 条款 / 开单人 -->
      <TextArea v-model="form.terms" :label="t('CRM.PI.FORM.TERMS')" />
      <div class="grid grid-cols-2 gap-3">
        <Input v-model="form.issuedBy" :label="t('CRM.PI.FORM.ISSUED_BY')" />
        <Input v-model="form.remark" :label="t('CRM.PI.FORM.REMARK')" />
      </div>
    </div>
  </Dialog>
</template>
