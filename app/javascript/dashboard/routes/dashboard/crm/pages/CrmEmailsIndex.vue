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
import EmailFoldersAPI from 'dashboard/api/crm/emailFolders';
import CrmAiAPI from 'dashboard/api/crm/ai';
import AgentAPI from 'dashboard/api/agents';
import { stripTextColorMarkers } from 'dashboard/helper/editorTextColor';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';
import CrmAddressIdentity from 'dashboard/components-next/CRM/CrmAddressIdentity.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmEmailsStore();
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');

const composeStore = useCrmComposeStore();
const searchTerm = ref('');
const selectedEmail = ref(null);
// 邮件范围：'mine' 我的邮件 / 'team' 团队邮件（默认看自己的）。
const mailScope = ref('mine');
// 能否看「团队邮件」（系统管理员或 CRM 团队负责人）——由后端 counts.can_view_team 决定，
// 决定是否显示「我的/团队」切换。业务员只看自己，不显示切换。
const canViewTeam = ref(false);
// 管理员可按业务员筛选（团队模式下）；'' = 全部成员。
const members = ref([]);
const activeOwner = ref('');
// 多邮箱侧边栏：可见范围内的邮箱 + 各自未读；activeMailbox '' = 全部收件。
const mailboxList = ref([]);
const activeMailbox = ref('');

// 实际用于过滤的负责人 id：只看自己的普通业务员由后端按角色收口（不传）；
// 能看团队者（管理员/团队负责人）「我的」= 自己，「团队」= 选中成员或全部（''，后端给其可见范围）。
const effectiveOwnerId = computed(() => {
  if (!isAdmin.value && !canViewTeam.value) return '';
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
// 自定义文件夹（个人）当前选中 id；非空时列表按该文件夹取数。
const activeCustomFolderId = ref(null);

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);

// —— 按日期分组（今天/昨天/本周/本月/更早按年月），互斥桶，列表已按日期倒序 ——
const dateBucket = dateStr => {
  const d = new Date(dateStr);
  if (Number.isNaN(d.getTime())) return { key: 'unknown', label: '未知日期' };
  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startYesterday = new Date(startToday);
  startYesterday.setDate(startToday.getDate() - 1);
  const dow = (startToday.getDay() + 6) % 7; // 周一=0
  const startWeek = new Date(startToday);
  startWeek.setDate(startToday.getDate() - dow);
  const startMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  if (d >= startToday) return { key: 'today', label: '今天' };
  if (d >= startYesterday) return { key: 'yesterday', label: '昨天' };
  if (d >= startWeek) return { key: 'week', label: '本周' };
  if (d >= startMonth) return { key: 'month', label: '本月' };
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  return { key: `${y}-${m}`, label: `${y}年${m}月` };
};
const groupedRecords = computed(() => {
  const groups = [];
  const map = {};
  records.value.forEach(r => {
    const b = dateBucket(r.emailDate);
    if (!map[b.key]) {
      map[b.key] = { key: b.key, label: b.label, items: [] };
      groups.push(map[b.key]);
    }
    map[b.key].items.push(r);
  });
  return groups;
});

// —— 多选 + 批量操作 ——
const selectedIds = ref([]);
const selectionActive = computed(() => selectedIds.value.length > 0);
const toggleSelect = id => {
  const i = selectedIds.value.indexOf(id);
  if (i >= 0) selectedIds.value.splice(i, 1);
  else selectedIds.value.push(id);
};
const allLoadedSelected = computed(
  () =>
    records.value.length > 0 &&
    selectedIds.value.length === records.value.length
);
const toggleSelectAll = () => {
  selectedIds.value = allLoadedSelected.value
    ? []
    : records.value.map(r => r.id);
};
const clearSelection = () => {
  selectedIds.value = [];
};
const bulkBusy = ref(false);
const bulkMarkRead = async isRead => {
  bulkBusy.value = true;
  try {
    await Promise.all(
      selectedIds.value.map(id => store.update({ id, isRead }))
    );
    useAlert(isRead ? '已标记为已读' : '已标记为未读');
    clearSelection();
    fetchCounts();
  } catch {
    useAlert('操作失败');
  } finally {
    bulkBusy.value = false;
  }
};
const bulkDelete = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除选中的 ${selectedIds.value.length} 封邮件？`))
    return;
  bulkBusy.value = true;
  try {
    await Promise.all(selectedIds.value.map(id => store.delete(id)));
    useAlert('已删除');
    clearSelection();
    fetchRecords();
    fetchCounts();
    fetchMailboxes();
  } catch {
    useAlert('删除失败');
  } finally {
    bulkBusy.value = false;
  }
};

const SEND_STATUSES = {
  DRAFT: { label: '草稿', class: 'bg-n-slate-3 text-n-slate-11' },
  SCHEDULED: { label: '定时发送', class: 'bg-n-amber-3 text-n-amber-11' },
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

// 列表头像按对方身份着色，与邮箱身份识别悬浮卡同色系：
// 同事/同事客户→琥珀，我的客户→蓝，公海→青，陌生人→灰，未识别→靛(默认)。
const AVATAR_STYLES = {
  colleague: 'bg-n-amber-4 text-n-amber-11',
  other: 'bg-n-amber-4 text-n-amber-11',
  mine: 'bg-n-blue-4 text-n-blue-11',
  public: 'bg-n-teal-4 text-n-teal-11',
  stranger: 'bg-n-slate-3 text-n-slate-11',
};
const avatarClass = record =>
  AVATAR_STYLES[record.counterpartyType] || 'bg-n-iris-4 text-n-iris-11';

// 卡片/阅读窗格显示的「对方」：收件箱看发件人，其余看收件人。
const counterparty = email =>
  email.folder === 'INBOX' ? email.fromAddress : email.toAddress;

// 地址串拆成单个邮箱（身份识别 chip 用）。
const splitAddresses = value =>
  (value || '')
    .split(/[;,]/)
    .map(s => s.trim())
    .filter(Boolean);

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

const baseParams = () => {
  if (activeCustomFolderId.value) {
    return { page: 1, email_folder_id: activeCustomFolderId.value };
  }
  return FILTER_FOLDERS.includes(activeFolder.value)
    ? { page: 1, filter: activeFolder.value }
    : { page: 1, folder: activeFolder.value };
};

// 当前 owner_id + mailbox 过滤参数（我的/团队 + 选中邮箱）。
const scopeParams = () => {
  const p = {};
  if (effectiveOwnerId.value) {
    p.owner_id = effectiveOwnerId.value;
  } else if (
    mailScope.value === 'team' &&
    (isAdmin.value || canViewTeam.value)
  ) {
    // 团队邮件（未指定具体成员）：排除自己，自己的在「我的邮件」里。
    p.exclude_owner_id = currentUserId.value;
  }
  if (activeMailbox.value) p.mailbox = activeMailbox.value;
  return p;
};

const fetchCounts = async () => {
  try {
    const { data } = await CrmEmailAPI.counts(scopeParams());
    counts.value = data;
    canViewTeam.value = !!data.can_view_team;
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
  // 列表按日期分组需一次多取（上限 200），覆盖近几个月，分组封数才准。
  const params = { ...baseParams(), ...scopeParams(), per_page: 200 };
  if (searchTerm.value.trim()) params.q = searchTerm.value.trim();
  selectedIds.value = [];
  store.get(params);
};

// 手动收取新邮件：立即为本人邮箱排拉取任务（比每分钟定时轮询更实时），
// 拉取异步、稍候分两次刷新列表/角标/邮箱（兼顾慢账户）。
const fetchingNow = ref(false);
const fetchTitle = '立即收取新邮件（否则每分钟自动收）';
const moreTitle = '更多';
const reloadMail = () => {
  fetchRecords();
  fetchCounts();
  fetchMailboxes();
};
const fetchNewMail = async () => {
  if (fetchingNow.value) return;
  fetchingNow.value = true;
  try {
    await CrmEmailAPI.fetchNow();
    useAlert('正在收取新邮件…');
    setTimeout(reloadMail, 3500);
    setTimeout(() => {
      reloadMail();
      fetchingNow.value = false;
    }, 8000);
  } catch {
    useAlert('收取失败');
    fetchingNow.value = false;
  }
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
  if (activeFolder.value === key && !activeCustomFolderId.value) return;
  activeFolder.value = key;
  activeCustomFolderId.value = null;
  activeMailbox.value = '';
  selectedEmail.value = null;
  fetchMailboxes();
  fetchCounts();
  fetchRecords();
};

// —— 自定义文件夹（个人私有：把选中邮件归集）——
const acctId = () => route.params.accountId;
const emailFolders = ref([]);
const foldersExpanded = ref(true);
const moveMenuOpen = ref(false);
const fetchFolders = async () => {
  try {
    const { data } = await EmailFoldersAPI.get(acctId());
    emailFolders.value = data.payload || [];
  } catch {
    emailFolders.value = [];
  }
};
const selectCustomFolder = id => {
  activeCustomFolderId.value = id;
  activeMailbox.value = '';
  selectedEmail.value = null;
  fetchRecords();
};
const createFolder = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt('新建文件夹名称');
  if (!name || !name.trim()) return null;
  try {
    const { data } = await EmailFoldersAPI.create(acctId(), name.trim());
    await fetchFolders();
    return data.id;
  } catch {
    useAlert('新建失败');
    return null;
  }
};
const deleteFolder = async folder => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `删除文件夹「${folder.name}」？里面的邮件会回到收件箱等原处。`
    )
  )
    return;
  try {
    await EmailFoldersAPI.delete(acctId(), folder.id);
    if (activeCustomFolderId.value === folder.id) setFolder('INBOX');
    await fetchFolders();
  } catch {
    useAlert('删除失败');
  }
};
// 批量移动到文件夹（folderId=null 移出到系统视图）
const moveToFolder = async folderId => {
  moveMenuOpen.value = false;
  try {
    await EmailFoldersAPI.move(acctId(), selectedIds.value, folderId);
    useAlert('已移动');
    clearSelection();
    fetchRecords();
    fetchCounts();
    fetchFolders();
  } catch {
    useAlert('移动失败');
  }
};
const moveToNewFolder = async () => {
  const id = await createFolder();
  if (id) moveToFolder(id);
};

const openCompose = prefill => composeStore.open(prefill);

// 写信面板发送/存草稿后刷新列表与角标。
const onComposeRefresh = () => {
  fetchRecords();
  fetchCounts();
};
// 常驻写信窗（挂在 CRM 布局层）发信/存草稿后，刷新本页邮件列表与角标。
watch(() => composeStore.refreshSeq, onComposeRefresh);

const emailOpens = ref([]);

// ---- AI 翻译 / 往来摘要（DeepSeek）状态 ----
const aiTranslation = ref(null); // { subject, body }
const aiTranslating = ref(false);
const translationCache = new Map(); // email.id -> { subject, body }（本页会话内缓存）
const aiSummary = ref(null); // { address, text }
const aiSummarizing = ref(false);

// 打开归属地：优先「城市, 国家」，无归属地时回退 IP。
const openLocation = open => {
  const place = [open.city, open.country].filter(Boolean).join(', ');
  return place || (open.ip ? `IP ${open.ip}` : '未知');
};
const selectEmail = async email => {
  selectedEmail.value = email;
  emailOpens.value = [];
  // 换邮件时收起 AI 翻译/摘要面板（翻译按邮件缓存，重开秒出）。
  aiTranslation.value = null;
  aiSummary.value = null;
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

const translateEmail = async email => {
  if (aiTranslating.value) return;
  if (aiTranslation.value) {
    aiTranslation.value = null; // 再点一次 = 收起
    return;
  }
  const cached = translationCache.get(email.id);
  if (cached) {
    aiTranslation.value = cached;
    return;
  }
  aiTranslating.value = true;
  try {
    const { data } = await CrmAiAPI.translate(email.id);
    translationCache.set(email.id, data);
    aiTranslation.value = data;
  } catch (e) {
    useAlert(e?.response?.data?.message || 'AI 翻译失败，请稍后再试');
  } finally {
    aiTranslating.value = false;
  }
};

// 往来摘要：对「对方地址」（收件箱=发件人，发件箱=第一个收件人）的所有可见往来。
const summarizeThread = async email => {
  if (aiSummarizing.value) return;
  const address = splitAddresses(counterparty(email))[0];
  if (!address) {
    useAlert('这封邮件没有对方地址');
    return;
  }
  aiSummarizing.value = true;
  try {
    const { data } = await CrmAiAPI.summarize(address);
    aiSummary.value = { address, text: data.summary };
  } catch (e) {
    useAlert(e?.response?.data?.message || 'AI 摘要失败，请稍后再试');
  } finally {
    aiSummarizing.value = false;
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
    focusReplyTop: true,
  });
};

const forward = email => {
  openCompose({
    toAddress: '',
    subject: email.subject?.startsWith('Fwd:')
      ? email.subject
      : `Fwd: ${email.subject || ''}`,
    body: quotedBody(email),
    focusReplyTop: true,
  });
};

// 作为附件转发：把原邮件整封打包成 .eml 当附件，新邮件正文留空。
const forwardAsAttachment = async email => {
  try {
    const { data } = await CrmEmailAPI.eml(email.id);
    const name = `${(email.subject || 'email').replace(/[/\\:*?"<>|]/g, '_')}.eml`;
    const file = new File([data], name, { type: 'message/rfc822' });
    openCompose({
      toAddress: '',
      subject: email.subject?.startsWith('Fwd:')
        ? email.subject
        : `Fwd: ${email.subject || ''}`,
      attachmentFiles: [file],
      crmCustomerId: email.crmCustomerId || null,
      contactId: email.contactId || null,
    });
  } catch {
    useAlert('生成邮件附件失败');
  }
};

const resend = async email => {
  await store.update({ id: email.id, sendNow: true });
  useAlert('已重新提交发送');
  fetchRecords();
};

// 编辑草稿：载入写信框就地编辑（收/抄/密/主题/正文/发件人/客户/已有附件全部回填）。
const editDraft = email => {
  openCompose({
    editId: email.id,
    toAddress: email.toAddress || '',
    ccAddress: email.ccAddress || '',
    bccAddress: email.bccAddress || '',
    subject: email.subject || '',
    body: email.body || '',
    fromAddress: email.fromAddress || '',
    files: email.files || [],
    crmCustomerId: email.crmCustomerId || null,
    contactId: email.contactId || null,
  });
};

// 删除邮件（草稿为主，任意邮件可删）：确认后删除并刷新列表/角标/邮箱。
const deleteEmail = async email => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('确定删除这封邮件？删除后不可恢复。')) return;
  try {
    await store.delete(email.id);
    if (selectedEmail.value?.id === email.id) selectedEmail.value = null;
    useAlert('已删除');
    fetchRecords();
    fetchCounts();
    fetchMailboxes();
  } catch {
    useAlert('删除失败');
  }
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

// 阅读栏「更多」下拉：把次要操作（转发/附件转发/重新发送/垃圾邮件/删除）收进去，避免按钮太挤。
const showMore = ref(false);
const moreMenuItems = computed(() => {
  const e = selectedEmail.value;
  if (!e) return [];
  const items = [
    {
      label: aiSummarizing.value ? '摘要生成中…' : 'AI 往来摘要',
      icon: 'i-lucide-scroll-text',
      run: () => summarizeThread(e),
    },
    { label: '转发', icon: 'i-lucide-forward', run: () => forward(e) },
    {
      label: '附件转发',
      icon: 'i-lucide-paperclip',
      run: () => forwardAsAttachment(e),
    },
  ];
  if (e.sendStatus === 'FAILED') {
    items.push({
      label: '重新发送',
      icon: 'i-lucide-refresh-cw',
      run: () => resend(e),
    });
  }
  if (['INBOX', 'SPAM'].includes(e.folder)) {
    items.push({
      label: spamLabel.value,
      icon: spamIcon.value,
      run: () => toggleSpam(e),
    });
  }
  items.push({
    label: '删除',
    icon: 'i-lucide-trash-2',
    action: 'delete',
    run: () => deleteEmail(e),
  });
  return items;
});
const onMoreAction = payload => {
  showMore.value = false;
  payload.run?.();
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
  fetchFolders();
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
  <div
    class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
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

        <!-- 文件夹：可折叠父项，点击展开子文件夹 -->
        <button
          class="flex items-center gap-2.5 px-3 py-2 text-sm rounded-lg transition-colors text-n-slate-11 hover:bg-n-alpha-1"
          @click="foldersExpanded = !foldersExpanded"
        >
          <Icon icon="i-lucide-folder" class="flex-shrink-0 size-4" />
          <span class="flex-1 text-left">文件夹</span>
          <Icon
            :icon="
              foldersExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-if="foldersExpanded"
          class="flex flex-col mb-1 border-l gap-0.5 ml-5 pl-1.5 border-n-weak"
        >
          <button
            v-for="f in emailFolders"
            :key="f.id"
            class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-md transition-colors group"
            :class="
              activeCustomFolderId === f.id
                ? 'bg-n-iris-2 text-n-iris-11 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="selectCustomFolder(f.id)"
          >
            <span class="flex-1 text-left truncate">{{ f.name }}</span>
            <span v-if="f.count" class="text-xs tabular-nums text-n-slate-10">
              {{ f.count }}
            </span>
            <Icon
              icon="i-lucide-trash-2"
              class="size-3.5 opacity-0 group-hover:opacity-100 hover:text-n-ruby-11"
              @click.stop="deleteFolder(f)"
            />
          </button>
          <button
            class="flex items-center gap-1 px-2 py-1.5 text-sm rounded-md text-n-slate-10 hover:bg-n-alpha-1"
            @click="createFolder"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            新建文件夹
          </button>
        </div>
      </nav>
    </aside>

    <!-- 中栏：邮件列表 -->
    <section
      class="flex flex-col flex-shrink-0 border-r w-[380px] border-n-weak bg-n-solid-1"
    >
      <div class="flex-shrink-0 px-4 pt-4 pb-3 border-b border-n-weak">
        <div class="flex items-center justify-between">
          <h1 class="text-lg font-medium text-n-slate-12">
            {{ activeFolderLabel }}
          </h1>
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10">
              {{
                t('CRM.EMAILS.LIST.COUNT', {
                  count: store.getMeta?.count || 0,
                  unread: counts.unread,
                })
              }}
            </span>
            <button
              class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11 disabled:opacity-60"
              :disabled="fetchingNow"
              :title="fetchTitle"
              @click="fetchNewMail"
            >
              <Icon
                icon="i-lucide-refresh-cw"
                class="size-3.5"
                :class="fetchingNow ? 'animate-spin' : ''"
              />
              {{ fetchingNow ? '收取中…' : '收取' }}
            </button>
          </div>
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
        <!-- 我的/团队 邮件切换（系统管理员 或 CRM 团队负责人）-->
        <div
          v-if="isAdmin || canViewTeam"
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
          <!-- 批量操作条：紧凑图标 + tooltip -->
          <div
            v-if="selectedIds.length"
            class="sticky top-0 z-10 flex items-center gap-2 px-3 py-2 border-b bg-n-iris-2 border-n-weak"
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              title="全选"
              :checked="allLoadedSelected"
              @change="toggleSelectAll"
            />
            <span class="text-xs whitespace-nowrap text-n-slate-11">
              已选 {{ selectedIds.length }}
            </span>
            <div class="flex items-center gap-0.5 ml-auto">
              <button
                class="flex items-center justify-center rounded size-8 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
                title="标记已读"
                :disabled="bulkBusy"
                @click="bulkMarkRead(true)"
              >
                <Icon icon="i-lucide-mail-open" class="size-5" />
              </button>
              <button
                class="flex items-center justify-center rounded size-8 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
                title="标记未读"
                :disabled="bulkBusy"
                @click="bulkMarkRead(false)"
              >
                <Icon icon="i-lucide-mail" class="size-5" />
              </button>
              <div class="relative">
                <button
                  class="flex items-center justify-center rounded size-8 text-n-slate-11 hover:bg-n-alpha-2"
                  title="移动至文件夹"
                  @click="moveMenuOpen = !moveMenuOpen"
                >
                  <Icon icon="i-lucide-folder-input" class="size-5" />
                </button>
                <template v-if="moveMenuOpen">
                  <div
                    class="fixed inset-0 z-20"
                    @click="moveMenuOpen = false"
                  />
                  <div
                    class="absolute right-0 z-30 mt-1 py-1 overflow-y-auto border rounded-lg shadow-lg min-w-[150px] max-h-64 border-n-weak bg-n-solid-1"
                  >
                    <button
                      v-for="f in emailFolders"
                      :key="f.id"
                      class="flex w-full px-3 py-1.5 text-sm text-left whitespace-nowrap hover:bg-n-alpha-1 text-n-slate-12"
                      @click="moveToFolder(f.id)"
                    >
                      {{ f.name }}
                    </button>
                    <div
                      v-if="emailFolders.length"
                      class="my-1 border-t border-n-weak"
                    />
                    <button
                      class="flex items-center w-full gap-1 px-3 py-1.5 text-sm text-left text-n-iris-11 hover:bg-n-alpha-1"
                      @click="moveToNewFolder"
                    >
                      <Icon icon="i-lucide-plus" class="size-3.5" />新建文件夹
                    </button>
                  </div>
                </template>
              </div>
              <button
                class="flex items-center justify-center rounded size-8 text-n-ruby-11 hover:bg-n-ruby-3 disabled:opacity-50"
                title="删除"
                :disabled="bulkBusy"
                @click="bulkDelete"
              >
                <Icon icon="i-lucide-trash-2" class="size-5" />
              </button>
              <button
                class="flex items-center justify-center rounded size-8 text-n-slate-10 hover:bg-n-alpha-2"
                title="取消"
                @click="clearSelection"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>

          <template v-for="group in groupedRecords" :key="group.key">
            <div
              class="flex items-center gap-2 px-4 py-1.5 text-xs font-medium bg-n-alpha-1 text-n-slate-11"
            >
              {{ group.label }}
              <span class="text-n-slate-10"
                >（{{ group.items.length }} 封）</span
              >
            </div>
            <div
              v-for="record in group.items"
              :key="record.id"
              class="flex items-center border-b group border-n-weak"
              :class="
                selectedEmail?.id === record.id
                  ? 'bg-n-iris-2'
                  : selectedIds.includes(record.id)
                    ? 'bg-n-iris-1'
                    : 'hover:bg-n-alpha-1'
              "
            >
              <button
                class="flex flex-1 min-w-0 gap-3 py-3 pl-1 pr-4 text-left"
                @click="selectEmail(record)"
              >
                <div
                  class="flex items-center justify-center flex-shrink-0 text-sm font-medium rounded-full size-9"
                  :class="avatarClass(record)"
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
                    {{ stripTextColorMarkers(record.body) || '（无正文）' }}
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
                      v-if="mailScope === 'team' && record.ownerName"
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
                <div
                  class="flex flex-col items-center flex-shrink-0 gap-2 self-start pt-1"
                >
                  <div class="flex items-center gap-1.5">
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
                        :icon="
                          record.isStarred ? 'i-ph-star-fill' : 'i-lucide-star'
                        "
                        class="size-4"
                      />
                    </button>
                  </div>
                  <label
                    class="flex items-center transition-opacity cursor-pointer"
                    :class="
                      selectionActive || selectedIds.includes(record.id)
                        ? 'opacity-100'
                        : 'opacity-0 group-hover:opacity-100'
                    "
                    @click.stop
                  >
                    <input
                      type="checkbox"
                      class="accent-n-iris-9"
                      :checked="selectedIds.includes(record.id)"
                      @change="toggleSelect(record.id)"
                    />
                  </label>
                </div>
              </button>
            </div>
          </template>
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
            <!-- 草稿：只留 编辑 + 删除 -->
            <template v-if="selectedEmail.folder === 'DRAFT'">
              <Button
                label="编辑"
                icon="i-lucide-pencil"
                size="sm"
                variant="faded"
                color="iris"
                @click="editDraft(selectedEmail)"
              />
              <Button
                label="删除"
                icon="i-lucide-trash-2"
                size="sm"
                variant="faded"
                color="ruby"
                @click="deleteEmail(selectedEmail)"
              />
            </template>
            <!-- 其他邮件：翻译 + 回复 + 全部回复 + 更多 -->
            <template v-else>
              <Button
                :label="aiTranslation ? '收起翻译' : '翻译'"
                :icon="
                  aiTranslating
                    ? 'i-lucide-loader-circle'
                    : 'i-lucide-languages'
                "
                size="sm"
                variant="faded"
                color="teal"
                :disabled="aiTranslating"
                @click="translateEmail(selectedEmail)"
              />
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
              <div class="relative">
                <button
                  class="flex items-center justify-center rounded-lg size-8 transition-colors text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-iris-11"
                  :title="moreTitle"
                  @click="showMore = !showMore"
                >
                  <Icon icon="i-lucide-more-horizontal" class="size-4" />
                </button>
                <template v-if="showMore">
                  <div class="fixed inset-0 z-40" @click="showMore = false" />
                  <DropdownMenu
                    :menu-items="moreMenuItems"
                    class="right-0 top-9"
                    @action="onMoreAction"
                  />
                </template>
              </div>
            </template>
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
                <span
                  class="inline-flex flex-wrap items-center gap-1 text-n-slate-11"
                >
                  <span class="text-n-slate-10">
                    {{ t('CRM.EMAILS.READING.FROM') }}
                  </span>
                  <CrmAddressIdentity
                    v-for="a in splitAddresses(selectedEmail.fromAddress)"
                    :key="`f-${a}`"
                    :address="a"
                  />
                  <span v-if="!selectedEmail.fromAddress">—</span>
                </span>
                <span
                  class="inline-flex flex-wrap items-center gap-1 text-n-slate-11"
                >
                  <span class="text-n-slate-10">
                    {{ t('CRM.EMAILS.READING.TO') }}
                  </span>
                  <CrmAddressIdentity
                    v-for="a in splitAddresses(selectedEmail.toAddress)"
                    :key="`t-${a}`"
                    :address="a"
                  />
                  <span v-if="!selectedEmail.toAddress">—</span>
                </span>
              </div>
              <div
                v-if="selectedEmail.ccAddress"
                class="inline-flex flex-wrap items-center gap-1 text-n-slate-11"
              >
                <span class="text-n-slate-10">
                  {{ t('CRM.EMAILS.READING.CC') }}
                </span>
                <CrmAddressIdentity
                  v-for="a in splitAddresses(selectedEmail.ccAddress)"
                  :key="`c-${a}`"
                  :address="a"
                />
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

          <!-- AI 往来摘要 -->
          <div
            v-if="aiSummary"
            class="p-4 mt-4 border rounded-lg border-n-iris-7 bg-n-iris-2"
          >
            <div class="flex items-center gap-2 mb-2">
              <Icon icon="i-lucide-scroll-text" class="size-4 text-n-iris-11" />
              <span class="text-sm font-medium text-n-iris-11">
                {{ `AI 往来摘要 · ${aiSummary.address}` }}
              </span>
              <span class="flex-1" />
              <button
                class="text-xs text-n-slate-10 hover:text-n-slate-12"
                @click="aiSummary = null"
              >
                收起
              </button>
            </div>
            <div
              class="text-sm leading-relaxed whitespace-pre-wrap text-n-slate-12"
            >
              {{ aiSummary.text }}
            </div>
          </div>

          <!-- AI 翻译 -->
          <div
            v-if="aiTranslation"
            class="p-4 mt-4 border rounded-lg border-n-teal-7 bg-n-teal-2"
          >
            <div class="flex items-center gap-2 mb-2">
              <Icon icon="i-lucide-languages" class="size-4 text-n-teal-11" />
              <span class="text-sm font-medium text-n-teal-11">AI 翻译</span>
              <span class="flex-1" />
              <button
                class="text-xs text-n-slate-10 hover:text-n-slate-12"
                @click="aiTranslation = null"
              >
                收起
              </button>
            </div>
            <p
              v-if="aiTranslation.subject"
              class="mb-2 text-sm font-medium text-n-slate-12"
            >
              {{ aiTranslation.subject }}
            </p>
            <div
              class="text-sm leading-relaxed whitespace-pre-wrap text-n-slate-12"
            >
              {{ aiTranslation.body }}
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
            {{
              stripTextColorMarkers(selectedEmail.body) ||
              t('CRM.EMAILS.READING.NO_BODY')
            }}
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
  </div>
</template>
