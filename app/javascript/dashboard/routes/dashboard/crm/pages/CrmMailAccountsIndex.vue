<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmMailAccountsStore } from 'dashboard/stores/crm/mailAccounts';
import MailAccountAPI from 'dashboard/api/crm/mailAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { t } = useI18n();
const store = useCrmMailAccountsStore();
const dialogRef = ref(null);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const PROVIDERS = {
  TENCENT_EXMAIL: '腾讯企业邮',
  NETEASE_QIYE: '网易企业邮',
  ALIYUN_QIYE: '阿里企业邮',
  CUSTOM: '自定义',
};
const providerOptions = Object.entries(PROVIDERS).map(([value, label]) => ({
  value,
  label,
}));
const sslOptions = [
  { value: 'true', label: 'SSL (465)' },
  { value: 'false', label: 'STARTTLS (587)' },
];

const L = {
  new: '新建邮箱',
  empty: '还没有发信邮箱，点右上「新建邮箱」并填 SMTP 授权码',
  active: '已启用',
  inactive: '已停用',
  edit: '编辑邮箱账户',
  delete: '删除',
  deleteConfirm: '确定删除该邮箱账户？',
  saved: '已保存',
  deleted: '已删除',
  error: '操作失败',
  signatureLabel: '签名',
  passwordKeep: '编辑时留空则不修改授权码',
  test: '测试连接',
  testing: '测试中…',
};

const enabledOptions = [
  { value: 'false', label: '不收信（仅发信）' },
  { value: 'true', label: '开启收件（IMAP）' },
];
const imapSslOptions = [
  { value: 'true', label: 'SSL (993)' },
  { value: 'false', label: '不加密 (143)' },
];

const editingId = ref(null);
const form = reactive({
  name: '',
  emailAddress: '',
  provider: 'TENCENT_EXMAIL',
  smtpHost: '',
  smtpPort: '',
  smtpPassword: '',
  useSsl: 'true',
  signature: '',
  imapEnabled: 'false',
  imapHost: '',
  imapPort: '',
  imapSsl: 'true',
});

const resetForm = () => {
  Object.assign(form, {
    name: '',
    emailAddress: '',
    provider: 'TENCENT_EXMAIL',
    smtpHost: '',
    smtpPort: '',
    smtpPassword: '',
    useSsl: 'true',
    signature: '',
    imapEnabled: 'false',
    imapHost: '',
    imapPort: '',
    imapSsl: 'true',
  });
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  dialogRef.value?.open();
};

const openEdit = record => {
  editingId.value = record.id;
  Object.assign(form, {
    name: record.name || '',
    emailAddress: record.emailAddress || '',
    provider: record.provider || 'TENCENT_EXMAIL',
    smtpHost: record.smtpHost || '',
    smtpPort: record.smtpPort ? String(record.smtpPort) : '',
    smtpPassword: '',
    useSsl: record.useSsl === false ? 'false' : 'true',
    signature: record.signature || '',
    imapEnabled: record.imapEnabled ? 'true' : 'false',
    imapHost: record.imapHost || '',
    imapPort: record.imapPort ? String(record.imapPort) : '',
    imapSsl: record.imapSsl === false ? 'false' : 'true',
  });
  dialogRef.value?.open();
};

const handleConfirm = async () => {
  if (!form.name.trim() || !form.emailAddress.trim()) return;
  const payload = {
    name: form.name.trim(),
    emailAddress: form.emailAddress.trim(),
    provider: form.provider,
    smtpHost: form.smtpHost.trim() || null,
    smtpPort: form.smtpPort ? Number(form.smtpPort) : null,
    useSsl: form.useSsl === 'true',
    signature: form.signature.trim() || null,
    imapEnabled: form.imapEnabled === 'true',
    imapHost: form.imapHost.trim() || null,
    imapPort: form.imapPort ? Number(form.imapPort) : null,
    imapSsl: form.imapSsl === 'true',
  };
  // 授权码留空时不覆盖（编辑场景）。
  if (form.smtpPassword) payload.smtpPassword = form.smtpPassword;
  try {
    if (editingId.value) {
      await store.update({ id: editingId.value, ...payload });
    } else {
      await store.create({
        ...payload,
        smtpPassword: form.smtpPassword || null,
      });
    }
    dialogRef.value?.close();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeRecord = async () => {
  // eslint-disable-next-line no-alert
  if (!editingId.value || !window.confirm(L.deleteConfirm)) return;
  try {
    await store.delete(editingId.value);
    dialogRef.value?.close();
    useAlert(L.deleted);
  } catch {
    useAlert(L.error);
  }
};

const toggleActive = record =>
  store.update({ id: record.id, isActive: !record.isActive });

// 连通性检测：实测 SMTP/IMAP 认证，弹出成功或失败原因（授权码错等）。
const testingId = ref(null);
const testAccount = async record => {
  testingId.value = record.id;
  try {
    const { data } = await MailAccountAPI.test(record.id);
    const smtp = data.smtp || {};
    if (!smtp.ok) {
      useAlert(`❌ ${record.name} 发信失败：${smtp.error || '认证失败'}`);
      return;
    }
    const imap = data.imap;
    const imapMsg = imap
      ? imap.ok
        ? '，收信正常'
        : `，但收信失败：${imap.error}`
      : '';
    useAlert(`✅ ${record.name} 发信正常${imapMsg}`);
  } catch {
    useAlert(L.error);
  } finally {
    testingId.value = null;
  }
};

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.MAIL_ACCOUNTS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-10">
          {{ t('CRM.MAIL_ACCOUNTS.HINT') }}
        </p>
      </div>
      <Button
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreate"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div v-if="isFetching" class="p-8 text-sm text-center text-n-slate-11">
        {{ t('CRM.EMAILS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="p-8 text-sm text-center text-n-slate-11"
      >
        {{ L.empty }}
      </div>
      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <div
          v-for="record in records"
          :key="record.id"
          class="flex flex-col gap-3 p-4 transition-shadow border cursor-pointer group rounded-2xl border-n-weak bg-n-solid-1 hover:shadow-sm hover:border-n-iris-7"
          @click="openEdit(record)"
        >
          <div class="flex items-start gap-3">
            <div
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-9 bg-n-iris-4 text-n-iris-11"
            >
              <Icon icon="i-lucide-mail" class="size-4" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-medium truncate text-n-slate-12">
                {{ record.name }}
              </h3>
              <p class="text-xs truncate text-n-slate-10">
                {{ record.emailAddress }}
              </p>
            </div>
            <span
              class="px-2 py-0.5 rounded-full text-[11px] flex-shrink-0 bg-n-alpha-2 text-n-slate-11"
            >
              {{ PROVIDERS[record.provider] || record.provider }}
            </span>
          </div>
          <p
            v-if="record.signature"
            class="text-[11px] line-clamp-2 text-n-slate-10"
          >
            {{ `${L.signatureLabel}：${record.signature}` }}
          </p>
          <div class="flex items-center justify-between pt-1">
            <button
              class="inline-flex items-center gap-1.5"
              @click.stop="toggleActive(record)"
            >
              <span
                class="relative w-8 h-4 rounded-full transition-colors"
                :class="record.isActive ? 'bg-n-teal-9' : 'bg-n-slate-5'"
              >
                <span
                  class="absolute top-0.5 size-3 rounded-full bg-white transition-all"
                  :class="record.isActive ? 'left-4' : 'left-0.5'"
                />
              </span>
              <span
                class="text-xs"
                :class="record.isActive ? 'text-n-teal-11' : 'text-n-slate-10'"
              >
                {{ record.isActive ? L.active : L.inactive }}
              </span>
            </button>
            <button
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11 disabled:opacity-60"
              :disabled="testingId === record.id"
              @click.stop="testAccount(record)"
            >
              <Icon
                :icon="
                  testingId === record.id
                    ? 'i-lucide-loader-circle'
                    : 'i-lucide-plug-zap'
                "
                class="size-3.5"
                :class="testingId === record.id ? 'animate-spin' : ''"
              />
              {{ testingId === record.id ? L.testing : L.test }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :title="editingId ? L.edit : t('CRM.MAIL_ACCOUNTS.CREATE.TITLE')"
      confirm-button-color="iris"
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <Input
            v-model="form.name"
            :label="t('CRM.MAIL_ACCOUNTS.FORM.NAME')"
            autofocus
          />
          <Input
            v-model="form.emailAddress"
            :label="t('CRM.MAIL_ACCOUNTS.FORM.EMAIL')"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM.MAIL_ACCOUNTS.FORM.PROVIDER') }}
            </label>
            <Select
              v-model="form.provider"
              class="w-full"
              :options="providerOptions"
            />
          </div>
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM.MAIL_ACCOUNTS.FORM.SSL') }}
            </label>
            <Select
              v-model="form.useSsl"
              class="w-full"
              :options="sslOptions"
            />
          </div>
        </div>
        <div v-if="form.provider === 'CUSTOM'" class="grid grid-cols-2 gap-4">
          <Input
            v-model="form.smtpHost"
            :label="t('CRM.MAIL_ACCOUNTS.FORM.HOST')"
          />
          <Input
            v-model="form.smtpPort"
            type="number"
            :label="t('CRM.MAIL_ACCOUNTS.FORM.PORT')"
          />
        </div>
        <Input
          v-model="form.smtpPassword"
          type="password"
          :label="t('CRM.MAIL_ACCOUNTS.FORM.PASSWORD')"
          :placeholder="
            editingId
              ? L.passwordKeep
              : t('CRM.MAIL_ACCOUNTS.FORM.PASSWORD_PLACEHOLDER')
          "
        />
        <!-- 收件设置（IMAP）：认证复用上面的授权码 -->
        <div class="pt-2 mt-1 border-t border-n-weak">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block mb-0.5 text-heading-3 text-n-slate-12">
                收件（IMAP）
              </label>
              <Select
                v-model="form.imapEnabled"
                class="w-full"
                :options="enabledOptions"
              />
            </div>
            <div v-if="form.imapEnabled === 'true'">
              <label class="block mb-0.5 text-heading-3 text-n-slate-12">
                收件加密
              </label>
              <Select
                v-model="form.imapSsl"
                class="w-full"
                :options="imapSslOptions"
              />
            </div>
          </div>
          <div
            v-if="form.imapEnabled === 'true' && form.provider === 'CUSTOM'"
            class="grid grid-cols-2 gap-4 mt-3"
          >
            <Input v-model="form.imapHost" label="IMAP 主机" />
            <Input v-model="form.imapPort" type="number" label="IMAP 端口" />
          </div>
          <p
            v-if="form.imapEnabled === 'true'"
            class="mt-1.5 text-xs text-n-slate-10"
          >
            开启后每 5 分钟自动拉取新邮件到收件箱，认证复用上方的授权码。
          </p>
        </div>
        <Input
          v-model="form.signature"
          :label="t('CRM.MAIL_ACCOUNTS.FORM.SIGNATURE')"
        />
        <button
          v-if="editingId"
          class="inline-flex items-center self-start gap-1 text-xs text-n-ruby-11 hover:underline"
          @click="removeRecord"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ L.delete }}
        </button>
      </div>
    </Dialog>
  </div>
</template>
