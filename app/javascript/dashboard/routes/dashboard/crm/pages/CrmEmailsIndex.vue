<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmEmailComposeDialog from 'dashboard/components-next/CRM/CrmEmailComposeDialog.vue';

const { t } = useI18n();
const store = useCrmEmailsStore();

const composeDialogRef = ref(null);
const detailDialogRef = ref(null);
const activeFolder = ref('INBOX');
const selectedEmail = ref(null);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const SEND_STATUSES = {
  DRAFT: { label: '草稿', class: 'bg-n-slate-3 text-n-slate-11' },
  PENDING: { label: '发送中', class: 'bg-n-amber-3 text-n-amber-11' },
  SENT: { label: '已发送', class: 'bg-n-teal-3 text-n-teal-11' },
  FAILED: { label: '发送失败', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

const folderTabs = [
  { key: 'INBOX', label: t('CRM.EMAILS.FOLDERS.INBOX') },
  { key: 'unread', label: t('CRM.EMAILS.FOLDERS.UNREAD') },
  { key: 'SENT', label: t('CRM.EMAILS.FOLDERS.SENT') },
  { key: 'DRAFT', label: t('CRM.EMAILS.FOLDERS.DRAFT') },
  { key: 'BULK', label: t('CRM.EMAILS.FOLDERS.BULK') },
];

const fetchRecords = () => {
  const params =
    activeFolder.value === 'unread'
      ? { page: 1, filter: 'unread' }
      : { page: 1, folder: activeFolder.value };
  store.get(params);
};

const setFolder = key => {
  activeFolder.value = key;
  fetchRecords();
};

const openCompose = () => composeDialogRef.value?.open();

const sendEmail = async payload => {
  try {
    await store.create(payload);
    composeDialogRef.value?.onSuccess();
    useAlert(t('CRM.EMAILS.COMPOSE.SUCCESS'));
  } catch {
    useAlert(t('CRM.EMAILS.COMPOSE.ERROR'));
  }
};

const openDetail = email => {
  selectedEmail.value = email;
  detailDialogRef.value?.open();
  if (email.folder === 'INBOX' && !email.isRead) {
    store.update({ id: email.id, isRead: true });
  }
};

const counterparty = email =>
  email.folder === 'INBOX' ? email.fromAddress : email.toAddress;

onMounted(fetchRecords);

const fmtTime = value => (value ? new Date(value).toLocaleString() : '—');
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.EMAILS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.EMAILS.COMPOSE.BUTTON')"
        icon="i-lucide-pen-line"
        color="blue"
        @click="openCompose"
      />
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in folderTabs"
        :key="tab.key"
        :label="tab.label"
        size="sm"
        :variant="activeFolder === tab.key ? 'solid' : 'faded'"
        :color="activeFolder === tab.key ? 'blue' : 'slate'"
        @click="setFolder(tab.key)"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.EMAILS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.EMAILS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMAILS.TABLE.SUBJECT') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMAILS.TABLE.COUNTERPARTY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMAILS.TABLE.CUSTOMER') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMAILS.TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.EMAILS.TABLE.DATE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in records"
            :key="record.id"
            class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
            @click="openDetail(record)"
          >
            <td
              class="px-3 py-2"
              :class="
                record.folder === 'INBOX' && !record.isRead
                  ? 'font-semibold text-n-slate-12'
                  : 'text-n-slate-11'
              "
            >
              <span
                v-if="record.folder === 'INBOX' && !record.isRead"
                class="inline-block w-2 h-2 mr-2 rounded-full bg-n-blue-9"
              />
              {{ record.subject || '(无主题)' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ counterparty(record) || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.customerName || '—' }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 rounded-full text-xs font-medium"
                :class="SEND_STATUSES[record.sendStatus]?.class"
              >
                {{ SEND_STATUSES[record.sendStatus]?.label }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ fmtTime(record.emailDate) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmEmailComposeDialog
      ref="composeDialogRef"
      :is-loading="isCreating"
      @send="sendEmail"
    />

    <Dialog
      ref="detailDialogRef"
      width="3xl"
      overflow-y-auto
      type="alert"
      :title="selectedEmail?.subject || '(无主题)'"
    >
      <div v-if="selectedEmail" class="flex flex-col gap-3 text-sm">
        <div class="text-n-slate-11">
          <div>{{ t('CRM.EMAILS.DETAIL.FROM') }}: {{ selectedEmail.fromAddress || '—' }}</div>
          <div>{{ t('CRM.EMAILS.DETAIL.TO') }}: {{ selectedEmail.toAddress || '—' }}</div>
          <div v-if="selectedEmail.ccAddress">
            {{ t('CRM.EMAILS.DETAIL.CC') }}: {{ selectedEmail.ccAddress }}
          </div>
          <div>{{ t('CRM.EMAILS.DETAIL.DATE') }}: {{ fmtTime(selectedEmail.emailDate) }}</div>
          <div v-if="selectedEmail.sendError" class="text-n-ruby-11">
            {{ t('CRM.EMAILS.DETAIL.SEND_ERROR') }}: {{ selectedEmail.sendError }}
          </div>
        </div>
        <div
          class="p-4 whitespace-pre-wrap border rounded-lg border-n-weak text-n-slate-12"
        >
          {{ selectedEmail.body || '（正文为空）' }}
        </div>
      </div>
    </Dialog>
  </div>
</template>
