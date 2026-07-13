<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';
import CrmEmailAPI from 'dashboard/api/crm/emails';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmEmailComposeDialog from 'dashboard/components-next/CRM/CrmEmailComposeDialog.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmEmailsStore();

const composeDialogRef = ref(null);
const searchTerm = ref('');
const selectedEmail = ref(null);
const counts = ref({ INBOX: 0, SENT: 0, DRAFT: 0, BULK: 0, unread: 0 });

const folderFromRoute = () =>
  route.query.filter === 'unread' ? 'unread' : route.query.folder || 'INBOX';
const activeFolder = ref(folderFromRoute());

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

// 左栏文件夹：收件箱/未读/发件箱/草稿/群发，带角标计数。
const FOLDERS = [
  { key: 'INBOX', label: '收件箱', icon: 'i-lucide-inbox', countKey: 'INBOX' },
  { key: 'unread', label: '未读', icon: 'i-lucide-mail', countKey: 'unread' },
  { key: 'SENT', label: '发件箱', icon: 'i-lucide-send', countKey: 'SENT' },
  {
    key: 'DRAFT',
    label: '草稿箱',
    icon: 'i-lucide-file-text',
    countKey: 'DRAFT',
  },
  { key: 'BULK', label: '群发箱', icon: 'i-lucide-users', countKey: 'BULK' },
];

const activeFolderLabel = computed(
  () => FOLDERS.find(f => f.key === activeFolder.value)?.label || '收件箱'
);

const initial = name => (name || '?').trim().charAt(0).toUpperCase();

// 卡片/阅读窗格显示的「对方」：收件箱看发件人，其余看收件人。
const counterparty = email =>
  email.folder === 'INBOX' ? email.fromAddress : email.toAddress;

const relTime = value => {
  if (!value) return '';
  const time = new Date(value).getTime();
  const diff = (Date.now() - time) / 1000;
  if (diff < 60) return '刚刚';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`;
  if (diff < 86400 * 7) return `${Math.floor(diff / 86400)} 天前`;
  return new Date(value).toLocaleDateString('zh-CN', {
    month: '2-digit',
    day: '2-digit',
  });
};

const fmtDateTime = value =>
  value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '—';

const fmtSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

const baseParams = () =>
  activeFolder.value === 'unread'
    ? { page: 1, filter: 'unread' }
    : { page: 1, folder: activeFolder.value };

const fetchCounts = async () => {
  try {
    const { data } = await CrmEmailAPI.counts();
    counts.value = data;
  } catch {
    // 角标失败不影响主流程
  }
};

const fetchRecords = () => {
  const params = baseParams();
  if (searchTerm.value.trim()) params.q = searchTerm.value.trim();
  store.get(params);
};

const setFolder = key => {
  if (activeFolder.value === key) return;
  activeFolder.value = key;
  selectedEmail.value = null;
  fetchRecords();
};

const openCompose = prefill => composeDialogRef.value?.open(prefill);

const sendEmail = async payload => {
  try {
    await store.create(payload);
    composeDialogRef.value?.onSuccess();
    useAlert(t('CRM.EMAILS.COMPOSE.SUCCESS'));
    fetchRecords();
    fetchCounts();
  } catch {
    useAlert(t('CRM.EMAILS.COMPOSE.ERROR'));
  }
};

const selectEmail = async email => {
  selectedEmail.value = email;
  if (email.folder === 'INBOX' && !email.isRead) {
    await store.update({ id: email.id, isRead: true });
    email.isRead = true;
    fetchCounts();
  }
};

// 回复/全部回复/转发：预填写信弹窗。
const quotedBody = email =>
  `\n\n------ 原邮件 ------\n发件人：${email.fromAddress || '—'}\n时间：${fmtDateTime(email.emailDate)}\n主题：${email.subject || '(无主题)'}\n\n${email.body || ''}`;

const reply = (email, all = false) => {
  openCompose({
    toAddress: email.fromAddress || '',
    ccAddress: all ? email.ccAddress || '' : '',
    subject: email.subject?.startsWith('Re:')
      ? email.subject
      : `Re: ${email.subject || ''}`,
    body: quotedBody(email),
    crmCustomerId: email.crmCustomerId || null,
    contactId: email.contactId || null,
  });
};

const forward = email => {
  openCompose({
    toAddress: '',
    subject: email.subject?.startsWith('Fwd:')
      ? email.subject
      : `Fwd: ${email.subject || ''}`,
    body: quotedBody(email),
  });
};

const resend = async email => {
  await store.update({ id: email.id, sendNow: true });
  useAlert('已重新提交发送');
  fetchRecords();
};

let searchTimer = null;
watch(searchTerm, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecords, 300);
});

onMounted(() => {
  fetchRecords();
  fetchCounts();
  if (route.query.compose) openCompose();
});

watch(
  () => [route.query.folder, route.query.filter, route.query.compose],
  () => {
    activeFolder.value = folderFromRoute();
    selectedEmail.value = null;
    fetchRecords();
    if (route.query.compose) openCompose();
  }
);
</script>

<template>
  <div class="flex w-full h-full overflow-hidden bg-n-background">
    <!-- 左栏：文件夹 -->
    <aside
      class="flex flex-col flex-shrink-0 border-r w-52 border-n-weak bg-n-solid-1"
    >
      <div class="p-3">
        <Button
          :label="t('CRM.EMAILS.COMPOSE.BUTTON')"
          icon="i-lucide-pen-line"
          color="amber"
          class="w-full"
          @click="openCompose()"
        />
      </div>
      <nav class="flex flex-col gap-0.5 px-2">
        <button
          v-for="folder in FOLDERS"
          :key="folder.key"
          class="flex items-center gap-2.5 px-3 py-2 text-sm rounded-lg transition-colors"
          :class="
            activeFolder === folder.key
              ? 'bg-n-amber-3 text-n-amber-11 font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="setFolder(folder.key)"
        >
          <Icon :icon="folder.icon" class="flex-shrink-0 size-4" />
          <span class="flex-1 text-left">{{ folder.label }}</span>
          <span
            v-if="counts[folder.countKey]"
            class="text-xs tabular-nums"
            :class="
              folder.key === 'unread' ? 'text-n-amber-11' : 'text-n-slate-10'
            "
          >
            {{ counts[folder.countKey] }}
          </span>
        </button>
      </nav>
    </aside>

    <!-- 中栏：邮件列表 -->
    <section
      class="flex flex-col flex-shrink-0 border-r w-[380px] border-n-weak bg-n-solid-1"
    >
      <div class="flex-shrink-0 px-4 pt-4 pb-3 border-b border-n-weak">
        <div class="flex items-baseline justify-between">
          <h1 class="text-lg font-medium text-n-slate-12">
            {{ activeFolderLabel }}
          </h1>
          <span class="text-xs text-n-slate-10">
            {{
              t('CRM.EMAILS.LIST.COUNT', {
                count: store.getMeta?.count || 0,
                unread: counts.unread,
              })
            }}
          </span>
        </div>
        <div class="relative mt-3">
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 left-3 top-1/2 size-4 text-n-slate-10"
          />
          <input
            v-model="searchTerm"
            type="text"
            :placeholder="t('CRM.EMAILS.LIST.SEARCH_PLACEHOLDER')"
            class="w-full py-2 pl-9 pr-3 text-sm border rounded-lg reset-base bg-n-alpha-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
          />
        </div>
      </div>

      <div class="flex-1 overflow-y-auto">
        <div v-if="isFetching" class="p-8 text-sm text-center text-n-slate-11">
          {{ t('CRM.EMAILS.LOADING') }}
        </div>
        <div
          v-else-if="!records.length"
          class="p-8 text-sm text-center text-n-slate-11"
        >
          {{ t('CRM.EMAILS.EMPTY') }}
        </div>
        <template v-else>
          <button
            v-for="record in records"
            :key="record.id"
            class="flex w-full gap-3 px-4 py-3 text-left transition-colors border-b border-n-weak"
            :class="
              selectedEmail?.id === record.id
                ? 'bg-n-amber-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="selectEmail(record)"
          >
            <div
              class="flex items-center justify-center flex-shrink-0 text-sm font-medium rounded-full size-9 bg-n-amber-4 text-n-amber-11"
            >
              {{ initial(counterparty(record)) }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between gap-2">
                <span
                  class="text-sm truncate"
                  :class="
                    record.folder === 'INBOX' && !record.isRead
                      ? 'font-semibold text-n-slate-12'
                      : 'font-medium text-n-slate-11'
                  "
                >
                  {{ counterparty(record) || '—' }}
                </span>
                <span class="flex-shrink-0 text-xs text-n-slate-10">
                  {{ relTime(record.emailDate) }}
                </span>
              </div>
              <div
                class="mt-0.5 text-sm truncate"
                :class="
                  record.folder === 'INBOX' && !record.isRead
                    ? 'font-medium text-n-slate-12'
                    : 'text-n-slate-11'
                "
              >
                {{ record.subject || '(无主题)' }}
              </div>
              <div class="mt-0.5 text-xs truncate text-n-slate-10">
                {{ record.body || '（无正文）' }}
              </div>
              <div class="flex items-center gap-2 mt-1.5">
                <span
                  v-if="record.folder !== 'INBOX'"
                  class="px-1.5 py-0.5 rounded text-[11px] font-medium"
                  :class="SEND_STATUSES[record.sendStatus]?.class"
                >
                  {{ SEND_STATUSES[record.sendStatus]?.label }}
                </span>
                <span
                  v-if="record.customerName"
                  class="px-1.5 py-0.5 rounded text-[11px] bg-n-alpha-2 text-n-slate-11 truncate max-w-[140px]"
                >
                  {{ record.customerName }}
                </span>
                <Icon
                  v-if="record.files?.length"
                  icon="i-lucide-paperclip"
                  class="size-3 text-n-slate-10"
                />
              </div>
            </div>
            <span
              v-if="record.folder === 'INBOX' && !record.isRead"
              class="flex-shrink-0 w-2 h-2 mt-1 rounded-full bg-n-amber-9"
            />
          </button>
        </template>
      </div>
    </section>

    <!-- 右栏：阅读窗格 -->
    <section class="flex flex-col flex-1 min-w-0 bg-n-background">
      <div
        v-if="!selectedEmail"
        class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
      >
        <Icon icon="i-lucide-mail-open" class="size-12 opacity-40" />
        <p class="text-sm">{{ t('CRM.EMAILS.READING.EMPTY') }}</p>
      </div>

      <template v-else>
        <!-- 工具栏 -->
        <div
          class="flex items-center justify-between flex-shrink-0 gap-3 px-6 py-3 border-b border-n-weak"
        >
          <div class="flex items-center min-w-0 gap-2">
            <h2 class="text-base font-medium truncate text-n-slate-12">
              {{ selectedEmail.subject || '(无主题)' }}
            </h2>
            <span
              class="px-2 py-0.5 rounded-full text-xs font-medium flex-shrink-0"
              :class="SEND_STATUSES[selectedEmail.sendStatus]?.class"
            >
              {{ SEND_STATUSES[selectedEmail.sendStatus]?.label }}
            </span>
          </div>
          <div class="flex items-center flex-shrink-0 gap-1">
            <Button
              :label="t('CRM.EMAILS.ACTIONS.REPLY')"
              icon="i-lucide-reply"
              size="sm"
              variant="faded"
              color="slate"
              @click="reply(selectedEmail)"
            />
            <Button
              :label="t('CRM.EMAILS.ACTIONS.REPLY_ALL')"
              icon="i-lucide-reply-all"
              size="sm"
              variant="faded"
              color="slate"
              @click="reply(selectedEmail, true)"
            />
            <Button
              :label="t('CRM.EMAILS.ACTIONS.FORWARD')"
              icon="i-lucide-forward"
              size="sm"
              variant="faded"
              color="slate"
              @click="forward(selectedEmail)"
            />
            <Button
              v-if="selectedEmail.sendStatus === 'FAILED'"
              :label="t('CRM.EMAILS.ACTIONS.RESEND')"
              icon="i-lucide-refresh-cw"
              size="sm"
              variant="faded"
              color="amber"
              @click="resend(selectedEmail)"
            />
          </div>
        </div>

        <div class="flex-1 px-6 py-5 overflow-y-auto">
          <!-- 收发信息 -->
          <div class="flex gap-3 pb-5 border-b border-n-weak">
            <div
              class="flex items-center justify-center flex-shrink-0 text-base font-medium rounded-full size-11 bg-n-amber-4 text-n-amber-11"
            >
              {{ initial(counterparty(selectedEmail)) }}
            </div>
            <div class="flex-1 min-w-0 space-y-1 text-sm">
              <div class="flex flex-wrap gap-x-6 gap-y-1">
                <span class="text-n-slate-11">
                  <span class="text-n-slate-10">
                    {{ t('CRM.EMAILS.READING.FROM') }}
                  </span>
                  {{ selectedEmail.fromAddress || '—' }}
                </span>
                <span class="text-n-slate-11">
                  <span class="text-n-slate-10">
                    {{ t('CRM.EMAILS.READING.TO') }}
                  </span>
                  {{ selectedEmail.toAddress || '—' }}
                </span>
              </div>
              <div v-if="selectedEmail.ccAddress" class="text-n-slate-11">
                <span class="text-n-slate-10">
                  {{ t('CRM.EMAILS.READING.CC') }}
                </span>
                {{ selectedEmail.ccAddress }}
              </div>
              <div class="flex flex-wrap items-center gap-x-6 gap-y-1">
                <span class="text-n-slate-10">
                  {{ fmtDateTime(selectedEmail.emailDate) }}
                </span>
                <span
                  v-if="selectedEmail.customerName"
                  class="inline-flex items-center gap-1 text-n-amber-11"
                >
                  <Icon icon="i-lucide-building-2" class="size-3.5" />
                  {{ selectedEmail.customerName }}
                </span>
                <span v-if="selectedEmail.ownerName" class="text-n-slate-10">
                  {{
                    t('CRM.EMAILS.READING.OWNER', {
                      name: selectedEmail.ownerName,
                    })
                  }}
                </span>
              </div>
            </div>
          </div>

          <!-- 发送失败原因 -->
          <div
            v-if="selectedEmail.sendError"
            class="flex items-start gap-2 p-3 mt-4 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-11"
          >
            <Icon icon="i-lucide-alert-triangle" class="size-4 mt-0.5" />
            <span>
              {{
                t('CRM.EMAILS.READING.SEND_ERROR', {
                  error: selectedEmail.sendError,
                })
              }}
            </span>
          </div>

          <!-- 正文 -->
          <div
            class="mt-5 text-sm leading-relaxed whitespace-pre-wrap text-n-slate-12"
          >
            {{ selectedEmail.body || t('CRM.EMAILS.READING.NO_BODY') }}
          </div>

          <!-- 附件 -->
          <div v-if="selectedEmail.files?.length" class="mt-6">
            <p class="mb-2 text-xs font-medium text-n-slate-10">
              {{
                t('CRM.EMAILS.READING.ATTACHMENTS', {
                  count: selectedEmail.files.length,
                })
              }}
            </p>
            <div class="grid grid-cols-2 gap-3">
              <a
                v-for="file in selectedEmail.files"
                :key="file.id"
                :href="file.url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 p-3 transition-colors border rounded-lg border-n-weak hover:bg-n-alpha-1"
              >
                <Icon
                  icon="i-lucide-file"
                  class="flex-shrink-0 size-8 text-n-amber-11"
                />
                <div class="min-w-0">
                  <p class="text-sm truncate text-n-slate-12">
                    {{ file.filename }}
                  </p>
                  <p class="text-xs text-n-slate-10">
                    {{ fmtSize(file.byteSize) }}
                  </p>
                </div>
              </a>
            </div>
          </div>
        </div>
      </template>
    </section>

    <CrmEmailComposeDialog
      ref="composeDialogRef"
      :is-loading="isCreating"
      @send="sendEmail"
    />
  </div>
</template>
