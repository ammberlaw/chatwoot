<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmMailAccountsStore } from 'dashboard/stores/crm/mailAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
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

const form = reactive({
  name: '',
  emailAddress: '',
  provider: 'TENCENT_EXMAIL',
  smtpHost: '',
  smtpPort: '',
  smtpPassword: '',
  useSsl: 'true',
  signature: '',
});

const providerOptions = Object.entries(PROVIDERS).map(([value, label]) => ({ value, label }));
const sslOptions = [
  { value: 'true', label: 'SSL (465)' },
  { value: 'false', label: 'STARTTLS (587)' },
];

const resetForm = () => {
  Object.assign(form, {
    name: '', emailAddress: '', provider: 'TENCENT_EXMAIL',
    smtpHost: '', smtpPort: '', smtpPassword: '', useSsl: 'true', signature: '',
  });
};

const openCreate = () => {
  resetForm();
  dialogRef.value?.open();
};

const handleConfirm = async () => {
  if (!form.name.trim() || !form.emailAddress.trim()) return;
  try {
    await store.create({
      name: form.name.trim(),
      emailAddress: form.emailAddress.trim(),
      provider: form.provider,
      smtpHost: form.smtpHost.trim() || null,
      smtpPort: form.smtpPort ? Number(form.smtpPort) : null,
      smtpPassword: form.smtpPassword || null,
      useSsl: form.useSsl === 'true',
      signature: form.signature.trim() || null,
    });
    dialogRef.value?.close();
    useAlert(t('CRM.MAIL_ACCOUNTS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.MAIL_ACCOUNTS.CREATE.ERROR'));
  }
};

const toggleActive = record =>
  store.update({ id: record.id, isActive: !record.isActive });

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div class="flex items-center justify-between px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">{{ t('CRM.MAIL_ACCOUNTS.HEADER') }}</h1>
      <Button :label="t('CRM.MAIL_ACCOUNTS.NEW')" icon="i-lucide-plus" color="blue" @click="openCreate" />
    </div>
    <div class="px-6 py-2 text-xs text-n-slate-11">{{ t('CRM.MAIL_ACCOUNTS.HINT') }}</div>

    <div class="flex-1 px-6 py-2">
      <div v-if="isFetching" class="p-8 text-center text-n-slate-11">Loading…</div>
      <div v-else-if="!records.length" class="p-8 text-center text-n-slate-11">
        {{ t('CRM.MAIL_ACCOUNTS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">{{ t('CRM.MAIL_ACCOUNTS.TABLE.NAME') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.MAIL_ACCOUNTS.TABLE.EMAIL') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.MAIL_ACCOUNTS.TABLE.PROVIDER') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.MAIL_ACCOUNTS.TABLE.ACTIVE') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="record in records" :key="record.id" class="border-b border-n-weak">
            <td class="px-3 py-2 font-medium text-n-slate-12">{{ record.name }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ record.emailAddress }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ PROVIDERS[record.provider] }}</td>
            <td class="px-3 py-2">
              <Button
                :label="record.isActive ? '已启用' : '已停用'"
                size="xs"
                :color="record.isActive ? 'teal' : 'slate'"
                variant="faded"
                @click="toggleActive(record)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :title="t('CRM.MAIL_ACCOUNTS.CREATE.TITLE')"
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <Input v-model="form.name" :label="t('CRM.MAIL_ACCOUNTS.FORM.NAME')" autofocus />
          <Input v-model="form.emailAddress" :label="t('CRM.MAIL_ACCOUNTS.FORM.EMAIL')" />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <Select v-model="form.provider" :label="t('CRM.MAIL_ACCOUNTS.FORM.PROVIDER')" :options="providerOptions" />
          <Select v-model="form.useSsl" :label="t('CRM.MAIL_ACCOUNTS.FORM.SSL')" :options="sslOptions" />
        </div>
        <div v-if="form.provider === 'CUSTOM'" class="grid grid-cols-2 gap-4">
          <Input v-model="form.smtpHost" :label="t('CRM.MAIL_ACCOUNTS.FORM.HOST')" />
          <Input v-model="form.smtpPort" type="number" :label="t('CRM.MAIL_ACCOUNTS.FORM.PORT')" />
        </div>
        <Input
          v-model="form.smtpPassword"
          type="password"
          :label="t('CRM.MAIL_ACCOUNTS.FORM.PASSWORD')"
          :placeholder="t('CRM.MAIL_ACCOUNTS.FORM.PASSWORD_PLACEHOLDER')"
        />
        <Input v-model="form.signature" :label="t('CRM.MAIL_ACCOUNTS.FORM.SIGNATURE')" />
      </div>
    </Dialog>
  </div>
</template>
