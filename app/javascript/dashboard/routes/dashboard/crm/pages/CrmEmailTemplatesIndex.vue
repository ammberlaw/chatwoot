<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmailTemplatesStore } from 'dashboard/stores/crm/emailTemplates';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const { t } = useI18n();
const store = useCrmEmailTemplatesStore();
const dialogRef = ref(null);

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const CATEGORIES = {
  DEVELOPMENT: '开发信',
  QUOTATION: '报价',
  FOLLOW_UP: '跟进',
  PAYMENT_REMINDER: '催款',
  GREETING: '节日问候',
  OTHER: '其他',
};

const form = reactive({ name: '', category: 'DEVELOPMENT', subjectTemplate: '', body: '', description: '' });
const categoryOptions = Object.entries(CATEGORIES).map(([value, label]) => ({ value, label }));

const openCreate = () => {
  Object.assign(form, { name: '', category: 'DEVELOPMENT', subjectTemplate: '', body: '', description: '' });
  dialogRef.value?.open();
};

const handleConfirm = async () => {
  if (!form.name.trim()) return;
  try {
    await store.create({
      name: form.name.trim(),
      category: form.category,
      subjectTemplate: form.subjectTemplate.trim() || null,
      body: form.body || null,
      description: form.description.trim() || null,
    });
    dialogRef.value?.close();
    useAlert(t('CRM.EMAIL_TEMPLATES.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.EMAIL_TEMPLATES.CREATE.ERROR'));
  }
};

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div class="flex items-center justify-between px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">{{ t('CRM.EMAIL_TEMPLATES.HEADER') }}</h1>
      <Button :label="t('CRM.EMAIL_TEMPLATES.NEW')" icon="i-lucide-plus" color="blue" @click="openCreate" />
    </div>

    <div class="flex-1 px-6 py-4">
      <div v-if="isFetching" class="p-8 text-center text-n-slate-11">Loading…</div>
      <div v-else-if="!records.length" class="p-8 text-center text-n-slate-11">
        {{ t('CRM.EMAIL_TEMPLATES.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">{{ t('CRM.EMAIL_TEMPLATES.TABLE.NAME') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.EMAIL_TEMPLATES.TABLE.CATEGORY') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.EMAIL_TEMPLATES.TABLE.SUBJECT') }}</th>
            <th class="px-3 py-2 font-medium">{{ t('CRM.EMAIL_TEMPLATES.TABLE.DESCRIPTION') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="record in records" :key="record.id" class="border-b border-n-weak">
            <td class="px-3 py-2 font-medium text-n-slate-12">{{ record.name }}</td>
            <td class="px-3 py-2">
              <span class="px-2 py-0.5 rounded-full text-xs bg-n-slate-3 text-n-slate-11">
                {{ CATEGORIES[record.category] }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ record.subjectTemplate || '—' }}</td>
            <td class="px-3 py-2 text-n-slate-11">{{ record.description || '—' }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="3xl"
      overflow-y-auto
      :title="t('CRM.EMAIL_TEMPLATES.CREATE.TITLE')"
      @confirm="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-2 gap-4">
          <Input v-model="form.name" :label="t('CRM.EMAIL_TEMPLATES.FORM.NAME')" autofocus />
          <Select v-model="form.category" :label="t('CRM.EMAIL_TEMPLATES.FORM.CATEGORY')" :options="categoryOptions" />
        </div>
        <Input v-model="form.subjectTemplate" :label="t('CRM.EMAIL_TEMPLATES.FORM.SUBJECT')" />
        <TextArea v-model="form.body" :label="t('CRM.EMAIL_TEMPLATES.FORM.BODY')" :rows="6" />
        <Input v-model="form.description" :label="t('CRM.EMAIL_TEMPLATES.FORM.DESCRIPTION')" />
      </div>
    </Dialog>
  </div>
</template>
