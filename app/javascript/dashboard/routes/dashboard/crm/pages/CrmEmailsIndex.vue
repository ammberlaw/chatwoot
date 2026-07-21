<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import DOMPurify from 'dompurify';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';
import CrmEmailAPI from 'dashboard/api/crm/emails';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmEmailComposeDialog from 'dashboard/components-next/CRM/CrmEmailComposeDialog.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmEmailsStore();
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');

const composeDialogRef = ref(null);
const searchTerm = ref('');
const selectedEmail = ref(null);
// 管理员的邮件范围：'mine' 我的邮件 / 'team' 团队邮件（默认看自己的）。
const mailScope = ref('mine');
// 管理员可按业务员筛选（团队模式下）；'' = 全部成员。
const members = ref([]);
const activeOwner = ref('');
// 多邮箱侧边栏：可见范围内的邮箱 + 各自未读；activeMailbox '' = 全部收件。
const mailboxList = ref([]);
const activeMailbox = ref('');

// 实际用于过滤的负责人 id：非管理员由后端按角色收口（不传）；
// 管理员「我的」= 自己，「团队」= 选中成员或全部（''）。
const effectiveOwnerId = computed(() => {
  if (!isAdmin.value) return '';
  return mailScope.value === 'mine' ? currentUserId.value : activeOwner.value;
});
const counts = ref({
  INBOX: 0,
  SENT: 0,
  DRAFT: 0,
  BULK: 0,
  SPAM: 0,
  unread: 0,
  starred: 0,
});

// filter 参数驱动的伪文件夹（非真实 folder 列）。
const FILTER_FOLDERS = ['unread', 'starred'];
const folderFromRoute = () => {
  if (FILTER_FOLDERS.includes(route.query.filter)) return route.query.filter;
  return route.query.folder || 'INBOX';
};
const activeFolder = ref(folderFromRoute());

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);

const SEND_STATUSES = {
  DRAFT: { label: '草稿', class: 'bg-n-slate-3 text-n-slate-11' },
  PENDING: { label: '发送中', class: 'bg-n-iris-3 text-n-iris-11' },
  SENT: { label: '已发送', class: 'bg-n-teal-3 text-n-teal-11' },
  FAILED: { label: '发送失败', class: 'bg-n-ruby-3 text-n-ruby-11' },
};

// 左栏文件夹：收件箱/未读/发件箱/草稿/群发，带角标计数。
const FOLDERS = [
  { key: 'INBOX', label: '收件箱', icon: 'i-lucide-inbox', countKey: 'INBOX' },
  { key: 'unread', label: '未读', icon: 'i-lucide-mail', countKey: 'unread' },
  { key: 'starred', label: '星标', icon: 'i-lucide-star', countKey: 'starred' },
  { key: 'SENT', label: '发件箱', icon: 'i-lucide-send', countKey: 'SENT' },
  {
    key: 'DRAFT',
    label: '草稿箱',
    icon: 'i-lucide-file-text',
    countKey: 'DRAFT',
  },
  { key: 'BULK', label: '群发箱', icon: 'i-lucide-users', countKey: 'BULK' },
  {
    key: 'SPAM',
    label: '垃圾邮件',
    icon: 'i-lucide-shield-alert',
    countKey: 'SPAM',
  },
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

// 富文本正文渲染前用 DOMPurify 消毒（收信方 HTML 可能不可信）。
const safeBodyHtml = computed(() =>
  selectedEmail.value?.bodyHtml
    ? DOMPurify.sanitize(selectedEmail.value.bodyHtml)
    : ''
);

const baseParams = () =>
  FILTER_FOLDERS.includes(activeFolder.value)
    ? { page: 1, filter: activeFolder.value }
    : { page: 1, folder: activeFolder.value };

// 当前 owner_id + mailbox 过滤参数（我的/团队 + 选中邮箱）。
const scopeParams = () => {
  const p = {};
  if (effectiveOwnerId.value) p.owner_id = effectiveOwnerId.value;
  if (activeMailbox.value) p.mailbox = activeMailbox.value;
  return p;
};

const fetchCounts = async () => {
  try {
    const { data } = await CrmEmailAPI.counts(scopeParams());
    counts.value = data;
  } catch {
    // 角标失败不影响主流程
  }
};

const fetchMailboxes = async () => {
  try {
    // 邮箱侧边栏恒为「本人配置的邮箱」，不随我的/团队变化；仅按当前文件夹取计数。
    const params = FILTER_FOLDERS.includes(activeFolder.value)
      ? { filter: activeFolder.value }
      : { folder: activeFolder.value };
    const { data } = await CrmEmailAPI.mailboxes(params);
    mailboxList.value = data || [];
  } catch {
    mailboxList.value = [];
  }
};

const fetchRecords = () => {
  const params = { ...baseParams(), ...scopeParams() };
  if (searchTerm.value.trim()) params.q = searchTerm.value.trim();
  store.get(params);
};

const onOwnerChange = () => {
  activeMailbox.value = '';
  selectedEmail.value = null;
  fetchMailboxes();
  fetchCounts();
  fetchRecords();
};

// 切换「我的/团队」：重置成员筛选与邮箱，刷新邮箱列表、角标、列表。
const setMailScope = scope => {
  if (mailScope.value === scope) return;
  mailScope.value = scope;
  activeOwner.value = '';
  activeMailbox.value = '';
  selectedEmail.value = null;
  fetchMailboxes();
  fetchCounts();
  fetchRecords();
};

// 切换邮箱：在当前文件夹下按该邮箱过滤（'' = 全部）。
const setMailbox = address => {
  if (activeMailbox.value === address) return;
  activeMailbox.value = address;
  selectedEmail.value = null;
  fetchCounts();
  fetchRecords();
};

const fetchMembers = async () => {
  if (!isAdmin.value) return;
  try {
    const { data } = await AgentAPI.get();
    members.value = data || [];
  } catch {
    members.value = [];
  }
};

const setFolder = key => {
  if (activeFolder.value === key) return;
  activeFolder.value = key;
  activeMailbox.value = '';
  selectedEmail.value = null;
  fetchMailboxes();
  fetchCounts();
  fetchRecords();
};

const openCompose = prefill => composeDialogRef.value?.open(prefill);

// 写信面板发送/存草稿后刷新列表与角标。
const onComposeRefresh = () => {
  fetchRecords();
  fetchCounts();
};

const emailOpens = ref([]);
// 打开归属地：优先「城市, 国家」，无归属地时回退 IP。
const openLocation = open => {
  const place = [open.city, open.country].filter(Boolean).join(', ');
  return place || (open.ip ? `IP ${open.ip}` : '未知');
};
const selectEmail = async email => {
  selectedEmail.value = email;
  emailOpens.value = [];
  if (email.folder === 'INBOX' && !email.isRead) {
    await store.update({ id: email.id, isRead: true });
    email.isRead = true;
    fetchCounts();
  }
  // 发出的追踪邮件：拉取每次打开的时间/IP 明细。
  if (email.tracked) {
    try {
      const { data } = await CrmEmailAPI.opens(email.id);
      emailOpens.value = data.payload || [];
    } catch {
      emailOpens.value = [];
    }
  }
};

// 星标：切换收藏，乐观更新后同步计数；在星标视图下取消则刷新列表移除。
const toggleStar = async email => {
  const next = !email.isStarred;
  email.isStarred = next;
  if (selectedEmail.value?.id === email.id)
    selectedEmail.value.isStarred = next;
  await store.update({ id: email.id, isStarred: next });
  fetchCounts();
  if (activeFolder.value === 'starred' && !next) fetchRecords();
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

const isSpam = computed(() => selectedEmail.value?.folder === 'SPAM');
const spamLabel = computed(() =>
  isSpam.value ? '移出垃圾邮件' : '标记垃圾邮件'
);
const spamIcon = computed(() =>
  isSpam.value ? 'i-lucide-shield-check' : 'i-lucide-shield-alert'
);

// 标记/移出垃圾邮件：改文件夹，刷新列表与角标。
const toggleSpam = async email => {
  const toSpam = email.folder !== 'SPAM';
  await store.update({ id: email.id, folder: toSpam ? 'SPAM' : 'INBOX' });
  useAlert(toSpam ? '已移入垃圾邮件' : '已移出垃圾邮件');
  selectedEmail.value = null;
  fetchRecords();
  fetchCounts();
  fetchMailboxes();
};

let searchTimer = null;
watch(searchTerm, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchRecords, 300);
});

onMounted(() => {
  fetchRecords();
  fetchCounts();
  fetchMembers();
  fetchMailboxes();
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
  <div class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <!-- 左栏：文件夹 -->
    <aside
      class="flex flex-col flex-shrink-0 border-r w-52 border-n-weak bg-n-solid-1"
    >
      <div class="p-3">
        <Button
          :label="t('CRM.EMAILS.COMPOSE.BUTTON')"
          icon="i-lucide-pen-line"
          color="iris"
          class="w-full"
          @click="openCompose()"
        />
      </div>
      <nav class="flex flex-col gap-0.5 px-2">
        <template v-for="folder in FOLDERS" :key="folder.key">
          <button
            class="flex items-center gap-2.5 px-3 py-2 text-sm rounded-lg transition-colors"
            :class="
              activeFolder === folder.key
                ? 'bg-n-iris-3 text-n-iris-11 font-medium'
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
                folder.key === 'unread' ? 'text-n-iris-11' : 'text-n-slate-10'
              "
            >
              {{ counts[folder.countKey] }}
            </span>
          </button>
          <!-- 当前文件夹下的多邮箱切换：全部 + 各邮箱（按可见范围）-->
          <div
            v-if="folder.key === activeFolder && mailboxList.length"
            class="flex flex-col mb-1 border-l gap-0.5 ml-5 pl-1.5 border-n-weak"
          >
            <button
              class="flex items-center px-2 py-1 text-xs transition-colors rounded-md"
              :class="
                activeMailbox === ''
                  ? 'text-n-iris-11 font-medium bg-n-iris-2'
                  : 'text-n-slate-10 hover:bg-n-alpha-1'
              "
              @click="setMailbox('')"
            >
              <span class="flex-1 text-left">{{ '全部' }}</span>
            </button>
            <button
              v-for="mb in mailboxList"
              :key="mb.address"
              class="flex items-center gap-1 px-2 py-1 text-xs transition-colors rounded-md"
              :class="
                activeMailbox === mb.address
                  ? 'text-n-iris-11 font-medium bg-n-iris-2'
                  : 'text-n-slate-10 hover:bg-n-alpha-1'
              "
              @click="setMailbox(mb.address)"
            >
              <span :title="mb.address" class="flex-1 text-left truncate">
                {{ mb.address }}
              </span>
              <span v-if="mb.count" class="tabular-nums text-n-slate-10">
                {{ mb.count }}
              </span>
            </button>
          </div>
        </template>
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
            class="w-full py-2 pl-9 pr-3 text-sm border rounded-lg reset-base bg-n-alpha-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </div>
        <!-- 我的/团队 邮件切换（仅管理员）-->
        <div
          v-if="isAdmin"
          class="flex gap-0.5 p-0.5 mt-2 rounded-lg bg-n-alpha-2"
        >
          <button
            v-for="opt in [
              { v: 'mine', l: '我的邮件' },
              { v: 'team', l: '团队邮件' },
            ]"
            :key="opt.v"
            class="flex-1 py-1 text-xs rounded-md transition-colors"
            :class="
              mailScope === opt.v
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm font-medium'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            @click="setMailScope(opt.v)"
          >
            {{ opt.l }}
          </button>
        </div>
        <!-- 团队模式下可下钻到指定成员 -->
        <div
          v-if="isAdmin && mailScope === 'team'"
          class="flex items-center gap-2 mt-2"
        >
          <Icon icon="i-lucide-users" class="size-4 text-n-slate-10" />
          <select
            v-model="activeOwner"
            class="flex-1 py-1.5 px-2 text-xs border rounded-lg reset-base bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            @change="onOwnerChange"
          >
            <option value="">{{ '全部成员' }}</option>
            <option v-for="m in members" :key="m.id" :value="m.id">
              {{ m.name }}
            </option>
          </select>
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
                ? 'bg-n-iris-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="selectEmail(record)"
          >
            <div
              class="flex items-center justify-center flex-shrink-0 text-sm font-medium rounded-full size-9 bg-n-iris-4 text-n-iris-11"
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
                  v-if="isAdmin && record.ownerName"
                  class="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[11px] bg-n-iris-3 text-n-iris-11 truncate max-w-[96px]"
                >
                  <Icon icon="i-lucide-user" class="size-3" />
                  {{ record.ownerName }}
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
                <span
                  v-if="record.tracked && record.openCount"
                  class="inline-flex items-center gap-0.5 text-[11px] text-n-teal-11"
                >
                  <Icon icon="i-lucide-eye" class="size-3" />
                  {{ record.openCount }}
                </span>
              </div>
            </div>
            <div class="flex flex-col items-center flex-shrink-0 gap-1.5">
              <span
                v-if="record.folder === 'INBOX' && !record.isRead"
                class="w-2 h-2 rounded-full bg-n-iris-9"
              />
              <button
                class="transition-colors"
                :class="
                  record.isStarred
                    ? 'text-n-iris-9'
                    : 'text-n-slate-8 hover:text-n-iris-9'
                "
                @click.stop="toggleStar(record)"
              >
                <Icon
                  :icon="record.isStarred ? 'i-ph-star-fill' : 'i-lucide-star'"
                  class="size-4"
                />
              </button>
            </div>
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
            <button
              class="flex items-center justify-center rounded-lg size-8 transition-colors hover:bg-n-alpha-1"
              :class="
                selectedEmail.isStarred
                  ? 'text-n-iris-9'
                  : 'text-n-slate-10 hover:text-n-iris-9'
              "
              :title="selectedEmail.isStarred ? '取消星标' : '加星标'"
              @click="toggleStar(selectedEmail)"
            >
              <Icon
                :icon="
                  selectedEmail.isStarred ? 'i-ph-star-fill' : 'i-lucide-star'
                "
                class="size-4"
              />
            </button>
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
              color="iris"
              @click="resend(selectedEmail)"
            />
            <Button
              v-if="['INBOX', 'SPAM'].includes(selectedEmail.folder)"
              :label="spamLabel"
              :icon="spamIcon"
              size="sm"
              variant="faded"
              color="slate"
              @click="toggleSpam(selectedEmail)"
            />
          </div>
        </div>

        <div class="flex-1 px-6 py-5 overflow-y-auto">
          <!-- 收发信息 -->
          <div class="flex gap-3 pb-5 border-b border-n-weak">
            <div
              class="flex items-center justify-center flex-shrink-0 text-base font-medium rounded-full size-11 bg-n-iris-4 text-n-iris-11"
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
                  class="inline-flex items-center gap-1 text-n-iris-11"
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

          <!-- 阅读追踪（仅发出的追踪邮件） -->
          <div
            v-if="selectedEmail.tracked"
            class="p-3 mt-4 border rounded-lg border-n-weak bg-n-alpha-1"
          >
            <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
              <span class="inline-flex items-center gap-1.5 font-medium">
                <Icon
                  icon="i-lucide-eye"
                  class="size-4"
                  :class="
                    selectedEmail.openCount
                      ? 'text-n-teal-11'
                      : 'text-n-slate-10'
                  "
                />
                <span
                  :class="
                    selectedEmail.openCount
                      ? 'text-n-teal-11'
                      : 'text-n-slate-10'
                  "
                >
                  {{
                    selectedEmail.openCount
                      ? `已读 · ${selectedEmail.openCount} 次`
                      : '未读'
                  }}
                </span>
              </span>
              <span v-if="selectedEmail.firstOpenedAt" class="text-n-slate-10">
                {{ `首次 ${fmtDateTime(selectedEmail.firstOpenedAt)}` }}
              </span>
              <span v-if="selectedEmail.lastOpenedAt" class="text-n-slate-10">
                {{ `最近 ${fmtDateTime(selectedEmail.lastOpenedAt)}` }}
              </span>
            </div>
            <div
              v-if="emailOpens.length"
              class="flex flex-col gap-1 pt-2 mt-2 border-t border-n-weak"
            >
              <div
                v-for="open in emailOpens"
                :key="open.id"
                class="flex items-center gap-2 text-xs text-n-slate-11"
              >
                <Icon
                  icon="i-lucide-map-pin"
                  class="size-3 text-n-slate-10 flex-shrink-0"
                />
                <span>{{ fmtDateTime(open.created_at) }}</span>
                <span class="text-n-slate-12">{{ openLocation(open) }}</span>
                <span
                  v-if="open.ip && (open.city || open.country)"
                  class="text-n-slate-10"
                >
                  {{ open.ip }}
                </span>
              </div>
            </div>
          </div>

          <!-- 正文 -->
          <!-- eslint-disable-next-line vue/no-v-html -->
          <div
            v-if="safeBodyHtml"
            class="mt-5 text-sm leading-relaxed prose-email text-n-slate-12"
            v-html="safeBodyHtml"
          />
          <div
            v-else
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
                  class="flex-shrink-0 size-8 text-n-iris-11"
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

    <CrmEmailComposeDialog ref="composeDialogRef" @refresh="onComposeRefresh" />
  </div>
</template>
