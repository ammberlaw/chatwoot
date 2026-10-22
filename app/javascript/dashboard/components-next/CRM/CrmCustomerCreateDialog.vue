<script setup>
/* global axios */
import { computed, reactive, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CrmStarRating from 'dashboard/components-next/CRM/CrmStarRating.vue';
import CrmBackgroundCheck from 'dashboard/components-next/CRM/CrmBackgroundCheck.vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'update', 'refresh']);

const { t } = useI18n();
const { accountId } = useAccount();
const dialogRef = ref(null);
const editingId = ref(null);
// 客户星级由累计成交额自动评定（只读展示）；编辑时取该客户当前成交额，新建时为 0。
const editingStarMicros = ref(0);

const form = reactive({
  name: '',
  customerCode: '',
  website: '',
  customerStatus: '',
  customerGroup: '',
  productGroup: '',
  sourceChannel: '',
  tradeCountry: '',
  primaryContactName: '',
  contactJobTitle: '',
  contactEmail: '',
  contactPhone: '',
  whatsApp: '',
  wechat: '',
  linkedin: '',
  address: '',
  contactPreference: '',
  customerRemark: '',
});

const statusOptions = [
  { value: 'PROSPECT', label: '潜在客户' },
  { value: 'FOLLOWING', label: '跟进中' },
  { value: 'WON', label: '成交客户' },
  { value: 'DORMANT', label: '沉默客户' },
  { value: 'LOST', label: '流失客户' },
];
// 客户分组 / 客户来源：从「客户设置」动态读取（含二级层级），不再写死。
const { ensureLoaded, groupOptions, sourceOptions } = useCrmOptions();
onMounted(ensureLoaded);

const productGroupOptions = [
  { value: 'TABLET', label: '平板电脑' },
  { value: 'COMMERCIAL_DISPLAY', label: '商显工控' },
];
const preferenceOptions = [
  { value: 'EMAIL', label: '邮件' },
  { value: 'PHONE', label: '电话' },
  { value: 'WHATSAPP', label: 'WhatsApp' },
  { value: 'WECHAT', label: '微信' },
];

const countryOptions = Object.entries(COUNTRY_LABELS).map(([value, label]) => ({
  value,
  label,
}));

const isEditing = computed(() => editingId.value !== null);
const isFormInvalid = computed(() => !form.name.trim());

// 附件
const attachments = ref([]);
const uploading = ref(false);
const fileInputRef = ref(null);

// 其他联系人（采购/经理等）：编辑时载入既有非主联系人，可增改；保存走 upsert（不删既有）。
const extraContacts = ref([]);
const addContact = () =>
  extraContacts.value.push({ name: '', jobTitle: '', email: '', phone: '' });
const removeContact = i => extraContacts.value.splice(i, 1);
const loadContacts = async id => {
  extraContacts.value = [];
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/contacts`,
      { params: { customer_id: id } }
    );
    extraContacts.value = (data.payload || [])
      .filter(c => !c.is_primary_contact)
      .map(c => ({
        name: c.name || '',
        jobTitle: c.job_title || '',
        email: c.email || '',
        phone: c.phone_number || '',
      }));
  } catch {
    extraContacts.value = [];
  }
};

const resetForm = () => {
  editingId.value = null;
  Object.keys(form).forEach(key => {
    form[key] = '';
  });
  attachments.value = [];
  extraContacts.value = [];
};

// 传 record 进入编辑模式；不传为新建。
const open = record => {
  resetForm();
  editingStarMicros.value = 0;
  if (record) {
    // 没 id = 只是拿一组预填值开新建（邮件中心背调后建档走这条）；别让 undefined 把弹窗认成编辑态。
    editingId.value = record.id ?? null;
    Object.keys(form).forEach(key => {
      form[key] = record[key] || '';
    });
    editingStarMicros.value =
      record.dealTotalAmountMicros ?? record.deal_total_amount_micros ?? 0;
    attachments.value = record.files || [];
    // 没有 id = 拿预填值开新建（如邮件中心背调后建档），不去拉联系人。
    if (record.id) loadContacts(record.id);
  }
  dialogRef.value?.open();
};

const closeDialog = () => dialogRef.value?.close();
const onSuccess = () => {
  resetForm();
  closeDialog();
};

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  const payload = {
    name: form.name.trim(),
    website: form.website.trim() || null,
    customerStatus: form.customerStatus || null,
    customerGroup: form.customerGroup || null,
    productGroup: form.productGroup || null,
    sourceChannel: form.sourceChannel || null,
    tradeCountry: form.tradeCountry || null,
    primaryContactName: form.primaryContactName.trim() || null,
    contactJobTitle: form.contactJobTitle.trim() || null,
    contactEmail: form.contactEmail.trim() || null,
    contactPhone: form.contactPhone.trim() || null,
    whatsApp: form.whatsApp.trim() || null,
    wechat: form.wechat.trim() || null,
    linkedin: form.linkedin.trim() || null,
    address: form.address.trim() || null,
    contactPreference: form.contactPreference || null,
    customerRemark: form.customerRemark.trim() || null,
    contacts: extraContacts.value
      .filter(x => x.email.trim())
      .map(x => ({
        name: x.name.trim(),
        job_title: x.jobTitle.trim(),
        email: x.email.trim(),
        phone: x.phone.trim(),
      })),
  };
  if (isEditing.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', payload);
  }
};

// 一键背调导入：公司名/网址用背调正式值刷新，国家/地址/领英只填空框，概况写进备注。
const applyBackground = payload => {
  const filled = [];
  const setAlways = (key, val, label) => {
    const v = String(val || '').trim();
    if (v && form[key] !== v) {
      form[key] = v;
      filled.push(label);
    }
  };
  const setIfBlank = (key, val, label) => {
    const v = String(val || '').trim();
    if (v && !String(form[key]).trim()) {
      form[key] = v;
      filled.push(label);
    }
  };
  setAlways('name', payload.name, '公司名');
  setAlways('website', payload.website, '网址');
  setIfBlank('address', payload.address, '地址');
  setIfBlank('linkedin', payload.linkedin, 'Linkedin');
  if (payload.countryCode && !form.tradeCountry) {
    form.tradeCountry = payload.countryCode;
    filled.push('国家');
  }
  if (payload.remarkBlock) {
    const stripped = String(form.customerRemark || '')
      .replace(/【AI 背调】[\s\S]*$/, '')
      .trim();
    form.customerRemark = stripped
      ? `${stripped}\n\n${payload.remarkBlock}`
      : payload.remarkBlock;
    filled.push('概况→备注');
  }
  useAlert(
    filled.length ? `已导入：${filled.join('、')}` : '没有可导入的新信息'
  );
};

// ── 附件上传 / 删除（独立于字段保存，即时生效）──
const attachApi = () =>
  `/api/v1/accounts/${accountId.value}/crm/customers/${editingId.value}/attach`;

const triggerUpload = () => fileInputRef.value?.click();

const onFilesSelected = async event => {
  const files = Array.from(event.target.files || []);
  if (!files.length || !editingId.value) return;
  uploading.value = true;
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  try {
    const { data } = await axios.post(attachApi(), fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    attachments.value = data.files || [];
    emit('refresh');
    useAlert(t('CRM.CUSTOMERS.ATTACH.UPLOAD_SUCCESS'));
  } catch {
    useAlert(t('CRM.CUSTOMERS.ATTACH.UPLOAD_ERROR'));
  } finally {
    uploading.value = false;
    event.target.value = '';
  }
};

const removeAttachment = async id => {
  try {
    const { data } = await axios.delete(`${attachApi()}/${id}`);
    attachments.value = data.files || [];
    emit('refresh');
  } catch {
    useAlert(t('CRM.CUSTOMERS.ATTACH.DELETE_ERROR'));
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
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-5">
      <span class="py-1 text-sm font-medium text-n-slate-12">
        {{
          isEditing
            ? t('CRM.CUSTOMERS.EDIT.TITLE')
            : t('CRM.CUSTOMERS.CREATE.TITLE')
        }}
      </span>

      <!-- 基本 -->
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.name"
          :label="t('CRM.CUSTOMERS.CREATE.FIELDS.NAME')"
          required
          :disabled="isLoading"
          autofocus
        />
        <Input
          v-model="form.customerCode"
          :label="t('CRM.CUSTOMERS.CREATE.FIELDS.CODE')"
          disabled
        />
        <Input
          v-model="form.website"
          label="公司网址 / 域名"
          :disabled="isLoading"
        />
        <!-- 套 Input 同款标签壳（flex-col gap-1 + label），与同行「公司网址」等高对齐，避免无标签下拉浮高 -->
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12"
            >国家 / 地区</label
          >
          <ComboBox
            v-model="form.tradeCountry"
            :options="countryOptions"
            placeholder="国家地区"
            search-placeholder="搜索国家/地区"
          />
        </div>
      </div>

      <!-- 一键背调（已建档客户也能补全）：抓官网 + Apollo 概况，一键导入公司名/网址/国家/概况 -->
      <CrmBackgroundCheck
        v-if="isEditing"
        :key="editingId"
        :name="form.name"
        :website="form.website"
        :email="form.contactEmail"
        @apply="applyBackground"
      />

      <!-- 业务 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        业务信息
      </div>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <SelectCard
          v-model="form.customerStatus"
          :options="statusOptions"
          placeholder="客户状态"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">客户星级</label>
          <div class="flex items-center h-9 gap-2">
            <CrmStarRating :micros="editingStarMicros" size="md" />
            <span class="text-xs text-n-slate-10"
              >系统按累计成交额自动评定</span
            >
          </div>
        </div>
        <SelectCard
          v-model="form.customerGroup"
          :options="groupOptions"
          placeholder="客户分组"
        />
        <SelectCard
          v-model="form.productGroup"
          :options="productGroupOptions"
          placeholder="产品分组"
        />
        <SelectCard
          v-model="form.sourceChannel"
          :options="sourceOptions"
          placeholder="客户来源"
        />
      </div>

      <!-- 联系 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        联系信息
      </div>
      <div class="grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
        <Input
          v-model="form.primaryContactName"
          label="主要联系人"
          :disabled="isLoading"
        />
        <Input
          v-model="form.contactJobTitle"
          label="职位"
          :disabled="isLoading"
        />
        <Input
          v-model="form.contactEmail"
          label="联系邮箱"
          :disabled="isLoading"
        />
        <Input
          v-model="form.contactPhone"
          label="联系电话"
          :disabled="isLoading"
        />
        <Input v-model="form.whatsApp" label="WhatsApp" :disabled="isLoading" />
        <Input v-model="form.wechat" label="微信" :disabled="isLoading" />
        <Input v-model="form.linkedin" label="Linkedin" :disabled="isLoading" />
        <!-- 套 Input 同款标签壳，与同行 Linkedin 等高对齐；block 撑满与左侧输入框同宽 -->
        <div class="flex flex-col min-w-0 gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">联系偏好</label>
          <SelectCard
            v-model="form.contactPreference"
            :options="preferenceOptions"
            placeholder="联系偏好"
            block
          />
        </div>
        <Input
          v-model="form.address"
          label="地址"
          :disabled="isLoading"
          class="sm:col-span-2"
        />
      </div>

      <TextArea
        v-model="form.customerRemark"
        :placeholder="t('CRM.CUSTOMERS.CREATE.FIELDS.REMARK')"
        :disabled="isLoading"
        :max-length="280"
        class="w-full"
        show-character-count
        auto-height
      />

      <!-- 其他联系人（采购/经理等）：可增改，任一邮箱来信自动归属本客户 -->
      <div class="flex flex-col gap-2">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          其他联系人
        </div>
        <p class="text-xs text-n-slate-10">
          采购、经理等其他邮箱可一并录入；任一邮箱来信都会自动识别归属本客户。
        </p>
        <div
          v-for="(ct, i) in extraContacts"
          :key="i"
          class="grid grid-cols-1 gap-2 sm:grid-cols-12 sm:items-center"
        >
          <input
            v-model="ct.name"
            class="h-9 px-3 text-sm border rounded-lg no-margin border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="姓名"
          />
          <input
            v-model="ct.jobTitle"
            class="h-9 px-3 text-sm border rounded-lg no-margin border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="职位"
          />
          <input
            v-model="ct.email"
            class="h-9 px-3 text-sm border rounded-lg no-margin border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="邮箱"
          />
          <input
            v-model="ct.phone"
            class="h-9 px-3 text-sm border rounded-lg no-margin border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-2"
            placeholder="电话（选填）"
          />
          <button
            type="button"
            class="h-9 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-2 sm:col-span-1"
            @click="removeContact(i)"
          >
            删除
          </button>
        </div>
        <button
          type="button"
          class="self-start h-9 px-3 text-sm border border-dashed rounded-lg no-margin border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          @click="addContact"
        >
          + 添加联系人
        </button>
      </div>

      <!-- 附件（仅编辑模式）-->
      <div v-if="isEditing" class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span
            class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
          >
            附件
          </span>
          <button
            type="button"
            class="flex items-center gap-1 h-8 px-3 text-sm border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="uploading"
            @click="triggerUpload"
          >
            <span class="i-lucide-paperclip size-4" />
            {{ uploading ? '上传中…' : '添加附件' }}
          </button>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onFilesSelected"
          />
        </div>
        <div v-if="!attachments.length" class="text-xs text-n-slate-10">
          暂无附件。可上传合同、报价单、名片等文件。
        </div>
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
            title="删除"
            @click="removeAttachment(file.id)"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="reset"
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="closeDialog"
        />
        <Button
          :label="
            isEditing ? t('CRM.CUSTOMERS.EDIT.SAVE') : t('CRM.CUSTOMERS.NEW')
          "
          color="iris"
          type="submit"
          :disabled="isFormInvalid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </template>
  </Dialog>
</template>
