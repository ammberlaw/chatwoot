<script setup>
/* global axios */
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import DOMPurify from 'dompurify';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';
import CrmEmailAPI from 'dashboard/api/crm/emails';
import EmailFoldersAPI from 'dashboard/api/crm/emailFolders';
import EmailLabelsAPI from 'dashboard/api/crm/emailLabels';
import CrmAiAPI from 'dashboard/api/crm/ai';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';
import { stripTextColorMarkers } from 'dashboard/helper/editorTextColor';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { useCrmComposeStore } from 'dashboard/stores/crm/compose';
import CrmAddressIdentity from 'dashboard/components-next/CRM/CrmAddressIdentity.vue';
import CrmBackgroundCheck from 'dashboard/components-next/CRM/CrmBackgroundCheck.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

// 星标原来一直用 n-iris-9。经典灰把整条 iris 压成了近黑（去掉画布上大面积的紫），
// 星标跟着就成了黑星；星标按惯例是黄的。只在经典灰下改，紫玻璃保持原样。
const STAR_ON = isClassicTheme() ? 'text-n-amber-9' : 'text-n-iris-9';
const STAR_HOVER = isClassicTheme()
  ? 'hover:text-n-amber-9'
  : 'hover:text-n-iris-9';

const { t } = useI18n();
const route = useRoute();
const store = useCrmEmailsStore();
const { isAdmin } = useAdmin();
const currentUserId = useMapGetter('getCurrentUserID');

const composeStore = useCrmComposeStore();
const searchTerm = ref('');
const selectedEmail = ref(null);
// 中栏邮件列表折叠：折叠后阅读窗格占满，读长邮件更舒服（记忆到本地）。
const listCollapsed = ref(
  localStorage.getItem('crmEmailListCollapsed') === '1'
);
watch(listCollapsed, v =>
  localStorage.setItem('crmEmailListCollapsed', v ? '1' : '0')
);
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
const FILTER_FOLDERS = ['unread', 'starred', 'tracking'];
const folderFromRoute = () => {
  if (FILTER_FOLDERS.includes(route.query.filter)) return route.query.filter;
  return route.query.folder || 'INBOX';
};
const activeFolder = ref(folderFromRoute());
// 自定义文件夹（个人）当前选中 id；非空时列表按该文件夹取数。
const activeCustomFolderId = ref(null);
// 追踪视图的「已打开/未打开」分栏：'1' 已打开、'0' 未打开。
const trackingOpened = ref('1');

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
// —— 会话视图（列表级折叠）：把当前列表按会话（规范化主题 + 同客户/对方）折叠，
// 每串只留最新一封 + 封数徽标；点开进阅读栏「会话往来」翻整串。开关记忆到本地。——
const threadListMode = ref(localStorage.getItem('crmEmailThreadMode') === '1');
watch(threadListMode, v =>
  localStorage.setItem('crmEmailThreadMode', v ? '1' : '0')
);
// 与后端 Crm::Email.normalize_thread 同口径：反复剥 Re:/Fwd:/回复:/转发: 等前缀后归一。
const THREAD_PREFIX_RE =
  /^\s*(?:re|r\s*e|fw|fwd|答复|回复|回覆|转发|轉發|答覆)\s*[:：]\s*/i;
const normalizeThreadJs = subject => {
  let s = (subject || '').trim();
  for (;;) {
    const stripped = s.replace(THREAD_PREFIX_RE, '');
    if (stripped === s) break;
    s = stripped;
  }
  return s.toLowerCase().replace(/\s+/g, ' ').trim();
};
const threadKeyOf = r => {
  const who = r.crmCustomerId
    ? `c${r.crmCustomerId}`
    : (splitAddresses(counterparty(r))[0] || '').toLowerCase();
  return `${who}::${normalizeThreadJs(r.subject)}`;
};
// records 已按日期倒序，故每串首见即最新一封。
const displayRecords = computed(() => {
  if (!threadListMode.value) return records.value;
  const seen = new Map();
  const out = [];
  records.value.forEach(r => {
    const key = normalizeThreadJs(r.subject)
      ? threadKeyOf(r)
      : `__single_${r.id}`;
    const hit = seen.get(key);
    if (hit) {
      hit._threadCount += 1;
      return;
    }
    const clone = { ...r, _threadCount: 1 };
    seen.set(key, clone);
    out.push(clone);
  });
  return out;
});
const groupedRecords = computed(() => {
  const groups = [];
  const map = {};
  displayRecords.value.forEach(r => {
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

// 批量打标签：给选中的多封邮件都加上某标签（已有则跳过），逐封 merge label_ids。
const bulkLabelMenuOpen = ref(false);
const bulkAddLabel = async labelId => {
  bulkLabelMenuOpen.value = false;
  bulkBusy.value = true;
  try {
    await Promise.all(
      selectedIds.value
        .map(id => {
          const rec = records.value.find(r => r.id === id);
          const cur = Array.isArray(rec?.labelIds) ? rec.labelIds : [];
          if (cur.includes(labelId)) return null;
          return store.update({ id, labelIds: [...cur, labelId] });
        })
        .filter(Boolean)
    );
    useAlert('已批量打标签');
    clearSelection();
    fetchRecords();
  } catch {
    useAlert('打标签失败');
  } finally {
    bulkBusy.value = false;
  }
};

const SEND_STATUSES = {
  DRAFT: { label: '草稿', class: STATUS_TONE.idle },
  SCHEDULED: { label: '定时发送', class: STATUS_TONE.busy },
  PENDING: { label: '发送中', class: STATUS_TONE.flow },
  SENT: { label: '已发送', class: STATUS_TONE.done },
  FAILED: { label: '发送失败', class: STATUS_TONE.fail },
};

// 发送状态角标只对「我们发出去的」有意义：收到的邮件入库时 send_status 也写成 SENT，
// 挂个绿色「已发送」会让人以为这封是自己发的，进而到收到的邮件上去找只有发出邮件才有的阅读追踪。
const RECEIVED_FOLDERS = ['INBOX', 'SPAM'];
const showSendBadge = email => !RECEIVED_FOLDERS.includes(email.folder);

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
  {
    key: 'tracking',
    label: '追踪信息',
    icon: 'i-lucide-radar',
    countKey: 'tracking',
  },
  {
    key: 'DISTRIBUTED',
    label: '分发给我的',
    icon: 'i-lucide-share-2',
    countKey: 'distributed',
  },
  {
    key: 'DISTRIBUTED_BY_ME',
    label: '我分发的',
    icon: 'i-lucide-forward',
    countKey: 'distributed_by_me',
    managerOnly: true, // 仅主管/管理员可见，与「分发给我的」对应
  },
];

// 系统文件夹：主管专属项（如「我分发的」）仅对管理员/CRM 团队负责人展示。
const systemFolders = computed(() =>
  FOLDERS.filter(f => !f.managerOnly || isAdmin.value || canViewTeam.value)
);

const activeFolderLabel = computed(
  () => FOLDERS.find(f => f.key === activeFolder.value)?.label || '收件箱'
);

const initial = name => (name || '?').trim().charAt(0).toUpperCase();

// 列表头像按对方身份着色，与邮箱身份识别悬浮卡同色系：
// 同事/同事客户→琥珀，我的客户→蓝，公海→青，陌生人→灰，未识别→靛(默认)。
// ⚠️ 经典灰主题把整条 blue 色阶压成了中性灰（_next-colors.scss 的「去蓝」），
// 「我的客户」在那个主题下会跟陌生人一样灰、建了档也看不出来；
// 所以头像带 data-counterparty，由主题层把经典灰下的 mine 换成石墨色（见同文件底部规则）。
const AVATAR_STYLES = {
  colleague: 'bg-n-amber-4 text-n-amber-11',
  other: 'bg-n-amber-4 text-n-amber-11',
  mine: 'bg-n-blue-4 text-n-blue-11',
  public: 'bg-n-teal-4 text-n-teal-11',
  stranger: STATUS_TONE.idle,
};
const avatarClass = record =>
  AVATAR_STYLES[record.counterpartyType] || 'bg-n-iris-4 text-n-iris-11';

// 卡片/阅读窗格显示的「对方」：收件箱看发件人，其余看收件人。
const counterparty = email =>
  email.folder === 'INBOX' ? email.fromAddress : email.toAddress;

// 列表显示「对方」：一串邮箱地址认不出是谁，优先用业务员自己备注的联系人名/客户名
// （后端按地址查联系人得出，见 build_counterparty_names），认不出才退回地址。
const counterpartyLabel = email =>
  email.counterpartyName || counterparty(email) || '—';

// 分发标记：像会话卡片标业务那样，在列表行上直接显示这封邮件的内部流转去向。
// 分发给我的显示是谁分的（我自己的名字没信息量），其余显示分给了谁。
// 名字单独拆出来放，只让名字截断——不然「外贸业务员小陈」这种长名会把后面的
// 「分发」「+2」一起吃掉，标签就看不出是什么意思了。
const distributionLabel = email => {
  if (email.distributedToMe && email.distributedBy) {
    return {
      prefix: '',
      name: email.distributedBy,
      suffix: ' 分发',
      title: `${email.distributedBy} 分发给我`,
    };
  }
  const names = email.distributedTo || [];
  if (!names.length) return null;
  return {
    prefix: '分发给 ',
    name: names[0],
    suffix: names.length > 1 ? ` +${names.length - 1}` : '',
    title: `分发给 ${names.join('、')}`,
  };
};

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

// ── 附件预览：图片走站内灯箱，PDF 走站内 iframe，其余仍下载 ──
const isImageFile = f =>
  (f.contentType || '').startsWith('image/') ||
  /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(f.filename || '');
const isPdfFile = f =>
  (f.contentType || '') === 'application/pdf' ||
  /\.pdf$/i.test(f.filename || '');
// Office 文档浏览器不能内联渲染，改为浏览器内转换：docx→HTML(mammoth)、
// xls/xlsx→表格(SheetJS)。全程前端完成、文档不出服务器。
// SheetJS 连 97-2003 的 .xls(BIFF) 一起认，所以两种后缀都放行；
// .doc 只有 mammoth 能转而它只认 docx，.pptx 没有转换器，这两类仍走下载。
const isDocxFile = f =>
  /\.docx$/i.test(f.filename || '') ||
  (f.contentType || '').includes('wordprocessingml');
const isExcelFile = f =>
  /\.xlsx?$/i.test(f.filename || '') ||
  (f.contentType || '').includes('spreadsheetml') ||
  (f.contentType || '') === 'application/vnd.ms-excel';
const isOfficeFile = f => isDocxFile(f) || isExcelFile(f);
// 附件列表一长，表格和文档共用同一个空白图标就扫不出哪个是哪个。
// 只按扩展名分图标，不动 canPreview 的判断（csv 仍然只能下载）。
const FILE_ICONS = [
  [/\.(xlsx?|csv)$/i, 'i-lucide-file-spreadsheet'],
  [/\.docx?$/i, 'i-lucide-file-type'],
  [/\.pdf$/i, 'i-lucide-file-text'],
  [/\.(zip|rar|7z|gz)$/i, 'i-lucide-file-archive'],
];
const fileIcon = f =>
  FILE_ICONS.find(([re]) => re.test(f.filename || ''))?.[1] || 'i-lucide-file';
const canPreview = f => isImageFile(f) || isPdfFile(f) || isOfficeFile(f);
const previewFile = ref(null);
// 附件 URL 带 Content-Disposition: attachment 会被浏览器强制下载、iframe 空白；
// 预览时先拉成 blob 再生成 blob: 内联地址，保证站内直接渲染、不触发下载。
const previewUrl = ref('');
const previewHtml = ref(''); // Office 文档转换后的 HTML（docx/xlsx）
const previewLoading = ref(false);
const openPreview = async f => {
  if (!canPreview(f)) {
    window.open(f.url, '_blank', 'noopener');
    return;
  }
  previewFile.value = f;
  previewUrl.value = '';
  previewHtml.value = '';
  previewLoading.value = true;
  try {
    if (isOfficeFile(f)) {
      const buf = await (await fetch(f.url)).arrayBuffer();
      if (isDocxFile(f)) {
        const mammoth = await import('mammoth');
        const { value } = await mammoth.convertToHtml({ arrayBuffer: buf });
        previewHtml.value = DOMPurify.sanitize(value || '（空文档）');
      } else {
        const XLSX = await import('xlsx');
        const wb = XLSX.read(buf, { type: 'array' });
        previewHtml.value = DOMPurify.sanitize(
          wb.SheetNames.map(
            name =>
              `<h3>${name}</h3>${XLSX.utils.sheet_to_html(wb.Sheets[name])}`
          ).join('')
        );
      }
    } else {
      const raw = await (await fetch(f.url)).blob();
      const type = isPdfFile(f)
        ? 'application/pdf'
        : raw.type || 'application/octet-stream';
      const blob = raw.type === type ? raw : new Blob([raw], { type });
      previewUrl.value = URL.createObjectURL(blob);
    }
  } catch {
    useAlert('预览加载失败，请点右上角下载查看');
  } finally {
    previewLoading.value = false;
  }
};
const closePreview = () => {
  if (previewUrl.value.startsWith('blob:'))
    URL.revokeObjectURL(previewUrl.value);
  previewUrl.value = '';
  previewHtml.value = '';
  previewFile.value = null;
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
  if (activeFolder.value === 'tracking') {
    return { page: 1, filter: 'tracking', opened: trackingOpened.value };
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
  selectedIds.value = [];
  // 分发给我的：跨负责人取数，走专用端点（不带 folder/owner 收口）。
  if (activeFolder.value === 'DISTRIBUTED') {
    store.getDistributed({ page: 1, per_page: 200 });
    return;
  }
  // 我分发的（主管/管理员）：走专用端点，列我下发过的邮件。
  if (activeFolder.value === 'DISTRIBUTED_BY_ME') {
    store.getDistributedByMe({ page: 1, per_page: 200 });
    return;
  }
  // 「往来邮件」视图：只按客户过滤、跨系统文件夹（收+发都进），不带 folder。
  // 否则按当前文件夹/范围取（列表按日期分组需一次多取，上限 200，分组封数才准）。
  const params = customerFilter.value
    ? {
        page: 1,
        customer_id: customerFilter.value.id,
        ...(forceAllScope.value ? {} : scopeParams()),
        per_page: 200,
      }
    : { ...baseParams(), ...scopeParams(), per_page: 200 };
  if (searchTerm.value.trim()) params.q = searchTerm.value.trim();
  if (activeLabelId.value) params.label_id = activeLabelId.value;
  store.get(params);
};

// ── 头像快捷卡（写跟进 / 往来邮件）+ 按客户过滤往来邮件 ──
const avatarCard = ref(null); // { record, top, left }
const customerFilter = ref(null); // { id, name }
// 从客户抽屉深链打开某封往来邮件时：往来邮件不按 owner 收口，确保目标邮件一定在列表里（否则管理员看他人邮件会被过滤掉）。
const forceAllScope = ref(false);
const openAvatarCard = (record, ev) => {
  const rect = ev.currentTarget.getBoundingClientRect();
  avatarCard.value = { record, top: rect.bottom + 6, left: rect.left };
};
const closeAvatarCard = () => {
  avatarCard.value = null;
};
// 写跟进：不跳转，在右侧抽屉里直接记一条跟进（POST /follow_up_notes）。
const followUpDrawer = ref(null); // { customerId, customerName }
const followUpText = ref('');
const followUpSaving = ref(false);
const cardWriteFollowUp = () => {
  const rec = avatarCard.value?.record;
  closeAvatarCard();
  if (!rec?.crmCustomerId) return;
  followUpDrawer.value = {
    customerId: rec.crmCustomerId,
    customerName: rec.customerName || counterparty(rec),
  };
  followUpText.value = '';
};
const closeFollowUp = () => {
  followUpDrawer.value = null;
  followUpText.value = '';
};
const saveFollowUp = async () => {
  const title = followUpText.value.trim();
  if (!title || !followUpDrawer.value) return;
  followUpSaving.value = true;
  try {
    await axios.post(
      `/api/v1/accounts/${route.params.accountId}/crm/follow_up_notes`,
      { note: { title, crm_customer_id: followUpDrawer.value.customerId } }
    );
    useAlert('跟进已保存');
    closeFollowUp();
  } catch {
    useAlert('跟进保存失败，请重试');
  } finally {
    followUpSaving.value = false;
  }
};
const cardShowCorrespondence = () => {
  const rec = avatarCard.value?.record;
  closeAvatarCard();
  if (!rec?.crmCustomerId) return;
  customerFilter.value = {
    id: rec.crmCustomerId,
    name: rec.customerName || counterparty(rec),
  };
  selectedEmail.value = null;
  searchTerm.value = '';
  fetchRecords();
};
// ── 阅读邮件时一键 AI 背调：对这封邮件的「对方」查公司底细，结果可直接写回客户档案 ──
// 已建档的只补空字段 + 追加概况备注（不覆盖业务员自己填的），没建档的用背调结果直接建。
const customersStore = useCrmCustomersStore();
const bgDrawer = ref(null); // { record, address, name }
const bgPanelRef = ref(null);
const bgSaving = ref(false);
const bgDialogRef = ref(null);

// toAddress 可能是「张三 <a@x.com>, b@y.com」：只取第一个地址，去掉显示名。
const firstAddress = raw => {
  const one = String(raw || '').split(',')[0] || '';
  const m = one.match(/<([^>]+)>/);
  return (m ? m[1] : one).trim();
};

// 背调面板正好盖住「邮件正文区」那一整块（上下左右都贴着它），而不是从屏幕右边拉一条通顶抽屉——
// 背调看的就是这封邮件，面板该待在这封邮件的地盘上。
// 宽高都要显式给：类名里的 w-full/h-full 是百分比，只给 left/top 的话会溢出到屏幕外。
// 量不到正文区（窄屏下它整块是隐藏的）就回落成原来贴右边的固定宽度抽屉。
const readerRef = ref(null);
const DRAWER_FALLBACK_WIDTH = 512; // max-w-lg
// 面板宽度上限：贴着正文区右边往左铺，正文区再宽也不会铺满——铺满了正文一点都看不见。
const DRAWER_MAX_WIDTH = 520;
const bgDrawerStyle = ref({});
const alignDrawerToReader = () => {
  const r = readerRef.value?.getBoundingClientRect?.();
  if (!r || r.width <= DRAWER_FALLBACK_WIDTH) {
    bgDrawerStyle.value = { maxWidth: `${DRAWER_FALLBACK_WIDTH}px` };
    return;
  }
  const width = Math.min(r.width, DRAWER_MAX_WIDTH);
  bgDrawerStyle.value = {
    left: `${Math.round(r.right - width)}px`,
    top: `${Math.round(r.top)}px`,
    width: `${Math.round(width)}px`,
    height: `${Math.round(r.height)}px`,
  };
};

const openBackgroundCheck = async record => {
  closeAvatarCard();
  if (!record) return;
  bgDrawer.value = {
    record,
    address: firstAddress(counterparty(record)),
    name: record.customerName || record.counterpartyName || '',
  };
  await nextTick();
  alignDrawerToReader();
  // 开着的时候拖窗口/折叠列表，正文区会变宽变窄，跟着重算一次。
  window.addEventListener('resize', alignDrawerToReader);
  bgPanelRef.value?.runBackgroundCheck();
};
const closeBackgroundCheck = () => {
  window.removeEventListener('resize', alignDrawerToReader);
  bgDrawer.value = null;
};

// 已建档：拉当前档案，只填空字段，备注里替换掉上一次的【AI 背调】段落。
const writeBackToCustomer = async payload => {
  const id = bgDrawer.value?.record?.crmCustomerId;
  bgSaving.value = true;
  try {
    const { data } = await CrmCustomerAPI.show(id);
    const cur = camelcaseKeys(data, { deep: true });
    const patch = {};
    const filled = [];
    const setIfBlank = (key, val, label) => {
      const v = String(val || '').trim();
      if (v && !String(cur[key] || '').trim()) {
        patch[key] = v;
        filled.push(label);
      }
    };
    setIfBlank('website', payload.website, '网址');
    setIfBlank('address', payload.address, '地址');
    setIfBlank('linkedin', payload.linkedin, 'Linkedin');
    setIfBlank('tradeCountry', payload.countryCode, '国家');
    if (payload.remarkBlock) {
      const stripped = String(cur.customerRemark || '')
        .replace(/【AI 背调】[\s\S]*$/, '')
        .trim();
      patch.customerRemark = stripped
        ? `${stripped}\n\n${payload.remarkBlock}`
        : payload.remarkBlock;
      filled.push('概况→备注');
    }
    if (!Object.keys(patch).length) {
      useAlert('档案里这些信息都已经有了，没有可写入的新内容');
      return;
    }
    await customersStore.update({ id, ...patch });
    useAlert(`已写入客户档案：${filled.join('、')}`);
    closeBackgroundCheck();
  } catch (e) {
    useAlert(e?.message || '写入客户档案失败，请重试');
  } finally {
    bgSaving.value = false;
  }
};

// 没建档：把背调结果当预填值打开建档弹窗（不带 id = 新建），联系邮箱用这封邮件的对方地址。
const openCreateWithBackground = payload => {
  const d = bgDrawer.value;
  bgDialogRef.value?.open({
    name: payload.name || d?.name || '',
    website: payload.website || '',
    address: payload.address || '',
    linkedin: payload.linkedin || '',
    tradeCountry: payload.countryCode || '',
    contactEmail: d?.address || '',
    customerRemark: payload.remarkBlock || '',
  });
  closeBackgroundCheck();
};

const applyBackgroundToCustomer = payload => {
  if (bgDrawer.value?.record?.crmCustomerId) {
    writeBackToCustomer(payload);
  } else {
    openCreateWithBackground(payload);
  }
};

// 建档成功后把这封邮件的对方地址收编为该客户的联系人，顺手把它散落的历史邮件挂上去。
const createCustomerFromBackground = async payload => {
  const address = firstAddress(counterparty(selectedEmail.value || {}));
  try {
    const record = await customersStore.create(payload);
    if (record?.id && address) {
      await CrmCustomerAPI.attachContact(record.id, {
        email: address,
        name: payload.primaryContactName || '',
      });
    }
    bgDialogRef.value?.onSuccess();
    useAlert('已建档，并把这个邮箱的往来邮件挂到该客户');
    fetchRecords();
  } catch (e) {
    useAlert(e?.message || '建档失败，请重试');
  }
};

const clearCustomerFilter = () => {
  customerFilter.value = null;
  forceAllScope.value = false;
  fetchRecords();
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

const ownerOptions = computed(() => [
  { value: '', label: '全部成员' },
  ...members.value.map(m => ({ value: m.id, label: m.name })),
]);

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
    // 只列 CRM 成员（排除人事/财务/非CRM/测试号），与其它 CRM 分配下拉统一口径。
    const { data } = await CrmAgentAPI.get(route.params.accountId, 'all');
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
};

const setFolder = key => {
  if (activeFolder.value === key && !activeCustomFolderId.value) return;
  activeFolder.value = key;
  activeCustomFolderId.value = null;
  activeLabelId.value = null;
  activeMailbox.value = '';
  customerFilter.value = null;
  forceAllScope.value = false;
  selectedEmail.value = null;
  fetchMailboxes();
  fetchCounts();
  fetchRecords();
};

// 追踪视图切换「已打开/未打开」分栏：换栏后重取列表。
const setTrackingTab = opened => {
  if (trackingOpened.value === opened) return;
  trackingOpened.value = opened;
  selectedEmail.value = null;
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
// 展开的文件夹 id 集合（有子级的才可展开）。
const expandedFolders = ref(new Set());
const toggleFolderExpand = id => {
  const s = new Set(expandedFolders.value);
  if (s.has(id)) s.delete(id);
  else s.add(id);
  expandedFolders.value = s;
};
// 把扁平文件夹（含 parent_id）拍平成带 depth / 有无子级的可见行，按层级缩进渲染（无限层级）。
const visibleFolders = computed(() => {
  const byParent = new Map();
  emailFolders.value.forEach(f => {
    const p = f.parent_id || null;
    if (!byParent.has(p)) byParent.set(p, []);
    byParent.get(p).push(f);
  });
  const rows = [];
  const walk = (parentId, depth) => {
    (byParent.get(parentId) || []).forEach(f => {
      const hasChildren = (byParent.get(f.id) || []).length > 0;
      rows.push({ ...f, depth, hasChildren });
      if (hasChildren && expandedFolders.value.has(f.id)) walk(f.id, depth + 1);
    });
  };
  walk(null, 0);
  return rows;
});
// 全量拍平（不受折叠影响）：移动至文件夹菜单用，按层级缩进列出所有文件夹。
const allFoldersFlat = computed(() => {
  const byParent = new Map();
  emailFolders.value.forEach(f => {
    const p = f.parent_id || null;
    if (!byParent.has(p)) byParent.set(p, []);
    byParent.get(p).push(f);
  });
  const rows = [];
  const walk = (parentId, depth) => {
    (byParent.get(parentId) || []).forEach(f => {
      rows.push({ ...f, depth });
      walk(f.id, depth + 1);
    });
  };
  walk(null, 0);
  return rows;
});

const createFolder = async (parentId = null) => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(parentId ? '新建子文件夹名称' : '新建文件夹名称');
  if (!name || !name.trim()) return null;
  try {
    const { data } = await EmailFoldersAPI.create(
      acctId(),
      name.trim(),
      parentId
    );
    if (parentId) {
      const s = new Set(expandedFolders.value);
      s.add(parentId);
      expandedFolders.value = s;
    }
    await fetchFolders();
    return data.id;
  } catch {
    useAlert('新建失败');
    return null;
  }
};
const createSubfolder = folder => createFolder(folder.id);
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

// —— 邮件标签（每账户一套定义；邮件上的归属存 label_ids 数组）——
const labels = ref([]);
const activeLabelId = ref(null);
const LABEL_COLORS = [
  'iris',
  'blue',
  'teal',
  'amber',
  'ruby',
  'violet',
  'slate',
];
// 字面量类名（Tailwind 只编译源码里出现的完整类名）。
const LABEL_DOT = {
  slate: 'bg-n-slate-9',
  iris: 'bg-n-iris-9',
  blue: 'bg-n-blue-9',
  teal: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  violet: 'bg-n-violet-9',
};
const LABEL_PILL = {
  slate: STATUS_TONE.idle,
  iris: 'bg-n-iris-3 text-n-iris-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  teal: STATUS_TONE.done,
  amber: STATUS_TONE.busy,
  ruby: STATUS_TONE.fail,
  violet: 'bg-n-violet-3 text-n-violet-11',
};
const labelDot = c => LABEL_DOT[c] || LABEL_DOT.slate;
const labelPill = c => LABEL_PILL[c] || LABEL_PILL.slate;
const labelById = computed(() =>
  Object.fromEntries(labels.value.map(l => [l.id, l]))
);
// 某封邮件当前挂的标签对象列表（按定义顺序）。
const emailLabels = email =>
  (email.labelIds || []).map(id => labelById.value[id]).filter(Boolean);

const fetchLabels = async () => {
  try {
    const { data } = await EmailLabelsAPI.get(acctId());
    labels.value = data.payload || [];
  } catch {
    labels.value = [];
  }
};
const setLabelFilter = id => {
  activeLabelId.value = activeLabelId.value === id ? null : id;
  selectedEmail.value = null;
  fetchRecords();
};
// 打/去标签：本地乐观更新 label_ids，再 PATCH（store.update 会把 labelIds → label_ids）。
const toggleEmailLabel = async (email, labelId) => {
  const cur = Array.isArray(email.labelIds) ? [...email.labelIds] : [];
  const i = cur.indexOf(labelId);
  if (i >= 0) cur.splice(i, 1);
  else cur.push(labelId);
  email.labelIds = cur;
  if (selectedEmail.value?.id === email.id) selectedEmail.value.labelIds = cur;
  try {
    await store.update({ id: email.id, labelIds: cur });
    if (activeLabelId.value && !cur.includes(activeLabelId.value))
      fetchRecords();
  } catch {
    useAlert('标签更新失败');
  }
};
const createLabel = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt('新建标签名称');
  if (!name || !name.trim()) return;
  const color = LABEL_COLORS[labels.value.length % LABEL_COLORS.length];
  try {
    await EmailLabelsAPI.create(acctId(), { name: name.trim(), color });
    await fetchLabels();
  } catch (e) {
    useAlert(e?.response?.data?.errors?.[0] || '新建失败（可能重名）');
  }
};
const deleteLabel = async label => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除标签「${label.name}」？会从所有邮件上移除该标签。`))
    return;
  try {
    await EmailLabelsAPI.delete(acctId(), label.id);
    if (activeLabelId.value === label.id) activeLabelId.value = null;
    await fetchLabels();
    fetchRecords();
  } catch {
    useAlert('删除失败');
  }
};
// 阅读栏「加标签」下拉开合。
const labelMenuOpen = ref(false);
// 左栏「标签」分组展开。
const labelsExpanded = ref(true);

const openCompose = prefill => composeStore.open(prefill);

// 写信面板发送/存草稿后刷新列表与角标。
const onComposeRefresh = () => {
  fetchRecords();
  fetchCounts();
};
// 常驻写信窗（挂在 CRM 布局层）发信/存草稿后，刷新本页邮件列表与角标。
watch(() => composeStore.refreshSeq, onComposeRefresh);

const emailOpens = ref([]);

// —— 会话线程：与当前邮件同一往来的全部邮件（后端实时按客户/对方地址+归一主题匹配）——
const threadEmails = ref([]);
const threadExpanded = ref(false);
const threadFilesExpanded = ref(false);
const fetchThread = async id => {
  threadEmails.value = [];
  threadFilesExpanded.value = false;
  try {
    const { data } = await CrmEmailAPI.thread(id);
    threadEmails.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch {
    threadEmails.value = [];
  }
};
// 会话附件汇总：把整串往来的附件拉平成一个列表。附件原本只在单封的阅读栏露出，
// 会话折叠后列表只剩最新一封，压在串里的文件等于没有入口——这里给它一个。
const threadFiles = computed(() =>
  threadEmails.value.flatMap(te =>
    (te.files || []).map(f => ({
      ...f,
      emailId: te.id,
      emailDate: te.emailDate,
      inbound: te.folder === 'INBOX',
    }))
  )
);
// 只有「别的邮件也带附件」时才出现——本封自己的附件正上方已经列了，不重复占一块。
const hasOtherThreadFiles = computed(() =>
  threadEmails.value.some(
    te => te.id !== selectedEmail.value?.id && te.files?.length
  )
);

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
// 追踪列表行：最近一次打开的归属地（城市, 国家）。
const trackingLocation = record =>
  [record.lastOpenCity, record.lastOpenCountry].filter(Boolean).join(', ');
const selectEmail = async email => {
  selectedEmail.value = email;
  emailOpens.value = [];
  // 换邮件时收起 AI 翻译/摘要面板（翻译按邮件缓存，重开秒出）。
  aiTranslation.value = null;
  aiSummary.value = null;
  // 拉取本封邮件所属会话（同往来的全部邮件），供阅读栏「会话往来」展示。
  fetchThread(email.id);
  if (
    activeFolder.value !== 'DISTRIBUTED' &&
    email.folder === 'INBOX' &&
    !email.isRead
  ) {
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

// 点附件上的日期跳到它所在的那封邮件（看上下文比只拿到文件有用）。
const jumpToThreadEmail = id => {
  const target = threadEmails.value.find(te => te.id === id);
  if (target && target.id !== selectedEmail.value?.id) selectEmail(target);
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

// 明天上午 9 点（转跟进任务的默认到期时间）。
const tomorrow9am = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(9, 0, 0, 0);
  return d.toISOString();
};

// 转跟进任务：把邮件落成一条待办（默认指派给自己、明天到期、类型=待回复邮件）。
// 关联到邮件所属客户/联系人（若有），处理完在客户跟进里可见。
const toFollowUpTask = async email => {
  try {
    await axios.post(
      `/api/v1/accounts/${route.params.accountId}/crm/follow_up_tasks`,
      {
        task: {
          title: `回复：${email.subject || '(无主题)'}`,
          task_type: 'EMAIL_REPLY',
          crm_customer_id: email.crmCustomerId || null,
          contact_id: email.contactId || null,
          due_at: tomorrow9am(),
        },
      }
    );
    useAlert('已转为跟进任务（指派给我 · 明天到期）');
  } catch {
    useAlert('转跟进任务失败，请重试');
  }
};

// 转商机：把邮件落成一条商机（需已关联客户）；金额/阶段到商机看板补充。
const toOpportunity = async email => {
  if (!email.crmCustomerId) {
    useAlert('该邮件未关联客户，无法转商机');
    return;
  }
  try {
    await axios.post(
      `/api/v1/accounts/${route.params.accountId}/crm/opportunities`,
      {
        opportunity: {
          name: email.subject || '(无主题)',
          crm_customer_id: email.crmCustomerId,
          sales_stage: 'NEEDS_CONFIRMED',
        },
      }
    );
    useAlert('已转为商机，可到商机看板补充金额与阶段');
  } catch (e) {
    useAlert(e?.response?.data?.error || '转商机失败，请重试');
  }
};

// 回复/全部回复/转发：预填写信弹窗。
const quotedBody = email =>
  `\n\n------ 原邮件 ------\n发件人：${email.fromAddress || '—'}\n时间：${fmtDateTime(email.emailDate)}\n主题：${email.subject || '(无主题)'}\n\n${email.body || ''}`;

// 原邮件引用：有 HTML（body_html）就走富文本独立引用块（保留颜色/加重/内嵌图/表格），
// 没有 HTML 才回退旧的纯文本引用塞进正文。
const quotePrefill = email =>
  email.bodyHtml
    ? {
        body: '',
        quoteHtml: email.bodyHtml,
        quotePlain: email.body || '',
        quoteMeta: {
          from: email.fromAddress || '—',
          date: fmtDateTime(email.emailDate),
          subject: email.subject || '(无主题)',
        },
      }
    : { body: quotedBody(email) };

// 「张三 <a@b.com>」→ a@b.com，只用来比对去重，展示仍用原串。
const bareAddress = raw => {
  const m = String(raw || '').match(/<([^>]+)>/);
  return (m ? m[1] : String(raw || '')).trim().toLowerCase();
};

// 全部回复的抄送：照标准邮件客户端的做法，把原邮件「其余收件人 + 原抄送」一起放进抄送，
// 只摘掉原发件人（他已在收件人栏）和自己的邮箱（否则等于抄送自己一份）。
// 只带原抄送是不够的——客户常把几个人一起写在收件人里、一个抄送都不写，那样点了等于没点。
const replyAllCc = email => {
  const mine = new Set(mailboxList.value.map(mb => bareAddress(mb.address)));
  mine.add(bareAddress(email.fromAddress));
  const seen = new Set();
  return [
    ...splitAddresses(email.toAddress),
    ...splitAddresses(email.ccAddress),
  ]
    .filter(addr => {
      const key = bareAddress(addr);
      if (!key || mine.has(key) || seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .join(', ');
};

const reply = (email, all = false) => {
  openCompose({
    toAddress: email.fromAddress || '',
    ccAddress: all ? replyAllCc(email) : '',
    subject: email.subject?.startsWith('Re:')
      ? email.subject
      : `Re: ${email.subject || ''}`,
    ...quotePrefill(email),
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
    ...quotePrefill(email),
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

// 再次编辑（类小满）：把已发邮件的收/抄/密/主题/正文/发件人/客户灌进写信框，当「新邮件」编辑后再发；
// 原有附件下载后作为新附件一并带上；不带 editId = 不动原件（原件仍留在发件箱）。
const reEdit = async email => {
  let attachmentFiles = [];
  try {
    attachmentFiles = await Promise.all(
      (email.files || []).map(async f => {
        const blob = await (await fetch(f.url)).blob();
        return new File([blob], f.filename, {
          type: blob.type || 'application/octet-stream',
        });
      })
    );
  } catch {
    attachmentFiles = [];
    useAlert('部分附件载入失败，正文已带入');
  }
  openCompose({
    toAddress: email.toAddress || '',
    ccAddress: email.ccAddress || '',
    bccAddress: email.bccAddress || '',
    subject: email.subject || '',
    body: email.body || '',
    fromAddress: email.fromAddress || '',
    attachmentFiles,
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

// —— 邮件内部分发（站内流转，不外发；含正文+附件+记录）——
// 分发目标成员列表：只列 CRM 成员（排除人事/财务/非CRM/测试号），与其它 CRM 分配下拉统一口径。
const distMembers = ref([]);
const loadDistMembers = async () => {
  if (distMembers.value.length) return;
  try {
    const { data } = await CrmAgentAPI.get(route.params.accountId, 'all');
    distMembers.value = data.payload || [];
  } catch {
    distMembers.value = [];
  }
};
const distributeDialog = ref(false);
const distributeEmail = ref(null);
const distributeIds = ref([]);
const distributeNote = ref('');
const distributeQuery = ref('');
const distributing = ref(false);
const openDistribute = e => {
  distributeEmail.value = e;
  distributeIds.value = [];
  distributeNote.value = '';
  distributeQuery.value = '';
  distributeDialog.value = true;
  loadDistMembers();
};
const distributeMembers = computed(() => {
  const q = distributeQuery.value.trim().toLowerCase();
  return distMembers.value
    .filter(m => m.id !== currentUserId.value)
    .filter(m => !q || `${m.name || ''}`.toLowerCase().includes(q));
});
const toggleDistId = id => {
  const i = distributeIds.value.indexOf(id);
  if (i >= 0) distributeIds.value.splice(i, 1);
  else distributeIds.value.push(id);
};
const submitDistribute = async () => {
  if (!distributeIds.value.length) {
    useAlert('请选择要分发的同事');
    return;
  }
  distributing.value = true;
  try {
    const { data } = await CrmEmailAPI.distribute(distributeEmail.value.id, {
      user_ids: distributeIds.value,
      note: distributeNote.value,
    });
    useAlert(`已分发给 ${data.distributed} 位同事`);
    distributeDialog.value = false;
    if (selectedEmail.value?.id === distributeEmail.value.id) {
      loadDistributions(selectedEmail.value.id);
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || '分发失败');
  } finally {
    distributing.value = false;
  }
};
// 分发历史（详情面板）
const distributions = ref([]);
const loadDistributions = async id => {
  try {
    const { data } = await CrmEmailAPI.distributions(id);
    distributions.value = data.payload || [];
  } catch {
    distributions.value = [];
  }
};
watch(selectedEmail, e => {
  distributions.value = [];
  if (e?.id) loadDistributions(e.id);
});

// 阅读栏「更多」下拉：把次要操作（转发/附件转发/重新发送/垃圾邮件/删除）收进去，避免按钮太挤。
const showMore = ref(false);
const moreMenuItems = computed(() => {
  const e = selectedEmail.value;
  if (!e) return [];
  const items = [
    {
      label: aiSummarizing.value ? '摘要生成中…' : 'AI 往来摘要',
      icon: 'i-lucide-scroll-text',
      menuClass: 'crm-ai-item',
      run: () => summarizeThread(e),
    },
    {
      label: 'AI 背调',
      icon: 'i-lucide-search-check',
      menuClass: 'crm-ai-item',
      run: () => openBackgroundCheck(e),
    },
    {
      label: '转跟进任务',
      icon: 'i-lucide-list-checks',
      run: () => toFollowUpTask(e),
    },
    ...(e.crmCustomerId
      ? [
          {
            label: '转商机',
            icon: 'i-lucide-trending-up',
            run: () => toOpportunity(e),
          },
        ]
      : []),
    { label: '转发', icon: 'i-lucide-forward', run: () => forward(e) },
    {
      label: '附件转发',
      icon: 'i-lucide-paperclip',
      run: () => forwardAsAttachment(e),
    },
    {
      label: '分发给同事',
      icon: 'i-lucide-share-2',
      run: () => openDistribute(e),
    },
  ];
  // 再次编辑：仅对「已发送」邮件（收件人才是真正的对方；收件箱邮件的收件人是自己）。
  if (e.sendStatus === 'SENT' || e.folder === 'SENT') {
    items.push({
      label: '再次编辑',
      icon: 'i-lucide-pencil-line',
      run: () => reEdit(e),
    });
  }
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

// 深链打开某封往来邮件：进入该客户「往来邮件」视图（不按 owner 收口），列表就绪后自动选中并打开目标邮件。
const openDeepLinkEmail = () => {
  const { customer_id: cid, customer_name: cname, email_id: eid } = route.query;
  customerFilter.value = { id: Number(cid), name: cname || '客户往来' };
  forceAllScope.value = true;
  selectedEmail.value = null;
  fetchRecords();
  const targetId = Number(eid);
  const stop = watch(
    records,
    list => {
      const target = list.find(r => r.id === targetId);
      if (target) {
        selectEmail(target);
        stop();
      }
    },
    { immediate: true }
  );
  // 兜底：8 秒后无论是否命中都停掉监听，避免常驻。
  setTimeout(stop, 8000);
};

onMounted(() => {
  if (route.query.email_id && route.query.customer_id) {
    openDeepLinkEmail();
  } else {
    fetchRecords();
  }
  fetchCounts();
  fetchMembers();
  fetchMailboxes();
  fetchFolders();
  fetchLabels();
  if (route.query.compose) openCompose();
});

watch(
  () => [
    route.query.folder,
    route.query.filter,
    route.query.compose,
    route.query.email_id,
  ],
  () => {
    // 已在邮件页时再次深链打开某封邮件（如从客户抽屉二次跳转）：走深链逻辑。
    if (route.query.email_id && route.query.customer_id) {
      openDeepLinkEmail();
      return;
    }
    activeFolder.value = folderFromRoute();
    selectedEmail.value = null;
    customerFilter.value = null; // 切换文件夹退出「往来邮件」客户过滤
    forceAllScope.value = false;
    fetchRecords();
    if (route.query.compose) openCompose();
  }
);
</script>

<template>
  <div
    class="flex w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <!-- 左栏：文件夹（手机端隐藏，让列表/阅读占满屏） -->
    <aside
      class="hidden md:flex flex-col flex-shrink-0 border-r w-52 border-n-weak bg-n-solid-1"
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
        <template v-for="folder in systemFolders" :key="folder.key">
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
          <div
            v-for="f in visibleFolders"
            :key="f.id"
            class="flex items-center rounded-md transition-colors group"
            :class="
              activeCustomFolderId === f.id
                ? 'bg-n-iris-2 text-n-iris-11 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            :style="{ paddingLeft: f.depth * 12 + 'px' }"
          >
            <button
              v-if="f.hasChildren"
              class="p-0.5 shrink-0"
              @click.stop="toggleFolderExpand(f.id)"
            >
              <Icon
                :icon="
                  expandedFolders.has(f.id)
                    ? 'i-lucide-chevron-down'
                    : 'i-lucide-chevron-right'
                "
                class="size-3.5 text-n-slate-10"
              />
            </button>
            <span v-else class="w-[18px] shrink-0" />
            <button
              class="flex items-center flex-1 min-w-0 gap-2 py-1.5 pr-1 text-sm text-left"
              @click="selectCustomFolder(f.id)"
            >
              <span class="flex-1 truncate">{{ f.name }}</span>
              <span v-if="f.count" class="text-xs tabular-nums text-n-slate-10">
                {{ f.count }}
              </span>
            </button>
            <Icon
              icon="i-lucide-folder-plus"
              title="新建子文件夹"
              class="mr-1 opacity-0 size-3.5 group-hover:opacity-100 shrink-0 hover:text-n-iris-11"
              @click.stop="createSubfolder(f)"
            />
            <Icon
              icon="i-lucide-trash-2"
              class="mr-1.5 opacity-0 size-3.5 group-hover:opacity-100 shrink-0 hover:text-n-ruby-11"
              @click.stop="deleteFolder(f)"
            />
          </div>
          <button
            class="flex items-center gap-1 px-2 py-1.5 text-sm rounded-md text-n-slate-10 hover:bg-n-alpha-1"
            @click="createFolder()"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            新建文件夹
          </button>
        </div>

        <!-- 标签：按标签跨文件夹筛选邮件（点选=过滤，再点=取消）-->
        <button
          class="flex items-center gap-2.5 px-3 py-2 mt-1 text-sm rounded-lg transition-colors text-n-slate-11 hover:bg-n-alpha-1"
          @click="labelsExpanded = !labelsExpanded"
        >
          <Icon icon="i-lucide-tag" class="flex-shrink-0 size-4" />
          <span class="flex-1 text-left">标签</span>
          <Icon
            :icon="
              labelsExpanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-if="labelsExpanded"
          class="flex flex-col mb-1 border-l gap-0.5 ml-5 pl-1.5 border-n-weak"
        >
          <div
            v-for="l in labels"
            :key="l.id"
            class="flex items-center rounded-md transition-colors group"
            :class="
              activeLabelId === l.id
                ? 'bg-n-iris-2 text-n-iris-11 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
          >
            <button
              class="flex items-center flex-1 min-w-0 gap-2 px-2 py-1.5 text-sm text-left"
              @click="setLabelFilter(l.id)"
            >
              <span
                class="rounded-full size-2 shrink-0"
                :class="labelDot(l.color)"
              />
              <span class="flex-1 truncate">{{ l.name }}</span>
            </button>
            <Icon
              icon="i-lucide-trash-2"
              class="mr-1.5 opacity-0 size-3.5 group-hover:opacity-100 shrink-0 hover:text-n-ruby-11"
              @click.stop="deleteLabel(l)"
            />
          </div>
          <button
            class="flex items-center gap-1 px-2 py-1.5 text-sm rounded-md text-n-slate-10 hover:bg-n-alpha-1"
            @click="createLabel"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
            新建标签
          </button>
        </div>
      </nav>
    </aside>

    <!-- 中栏折叠后的细条：只留一个展开按钮，把空间让给阅读窗格（仅桌面） -->
    <div
      v-if="listCollapsed"
      class="hidden md:flex flex-col items-center flex-shrink-0 w-10 gap-3 py-3 border-r border-n-weak bg-n-solid-1"
    >
      <button
        class="flex items-center justify-center rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11"
        title="展开邮件列表"
        @click="listCollapsed = false"
      >
        <Icon icon="i-lucide-panel-left-open" class="size-5" />
      </button>
      <span
        class="text-xs font-medium tracking-wide text-n-slate-11 [writing-mode:vertical-rl]"
      >
        {{ activeFolderLabel }}
      </span>
    </div>

    <!-- 中栏：邮件列表（手机端占满，选中邮件后让位给阅读窗格） -->
    <section
      v-show="!listCollapsed"
      class="flex-col flex-shrink-0 border-r w-full md:w-[380px] border-n-weak bg-n-solid-1"
      :class="selectedEmail ? 'hidden md:flex' : 'flex'"
    >
      <div class="flex-shrink-0 px-4 pt-4 pb-3 border-b border-n-weak">
        <div class="flex items-center justify-between gap-2 flex-wrap">
          <h1 class="text-lg font-medium text-n-slate-12">
            {{ activeFolderLabel }}
          </h1>
          <div class="flex items-center flex-wrap gap-2">
            <span class="text-xs text-n-slate-10">
              {{
                t('CRM.EMAILS.LIST.COUNT', {
                  count: store.getMeta?.count || 0,
                  unread: counts.unread,
                })
              }}
            </span>
            <button
              class="inline-flex items-center gap-1 px-2.5 min-h-9 md:min-h-0 md:py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11 disabled:opacity-60"
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
            <button
              class="inline-flex items-center gap-1 px-2.5 min-h-9 md:min-h-0 md:py-1 text-xs rounded-md hover:bg-n-alpha-2"
              :class="
                threadListMode
                  ? 'text-n-iris-11 bg-n-iris-3'
                  : 'text-n-slate-11 hover:text-n-iris-11'
              "
              title="会话视图：把同一往来的邮件折叠成一串"
              @click="threadListMode = !threadListMode"
            >
              <Icon icon="i-lucide-messages-square" class="size-3.5" />
              会话
            </button>
            <button
              class="hidden md:inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-iris-11"
              title="折叠列表，读信更宽"
              @click="listCollapsed = true"
            >
              <Icon icon="i-lucide-panel-left-close" class="size-3.5" />
              收起
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
          data-tabbar="page-block"
        >
          <button
            v-for="opt in [
              { v: 'mine', l: '我的邮件' },
              { v: 'team', l: '团队邮件' },
            ]"
            :key="opt.v"
            :aria-selected="mailScope === opt.v"
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
          <SelectCard
            v-model="activeOwner"
            :options="ownerOptions"
            block
            @update:model-value="onOwnerChange"
          />
        </div>
        <!-- 追踪视图：已打开 / 未打开 分栏 + 追踪说明 -->
        <template v-if="activeFolder === 'tracking'">
          <div class="flex gap-0.5 p-0.5 mt-2 rounded-lg bg-n-alpha-2">
            <button
              v-for="opt in [
                { v: '1', l: '已打开邮件' },
                { v: '0', l: '未打开邮件' },
              ]"
              :key="opt.v"
              class="flex-1 py-1 text-xs rounded-md transition-colors"
              :class="
                trackingOpened === opt.v
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm font-medium'
                  : 'text-n-slate-10 hover:text-n-slate-12'
              "
              @click="setTrackingTab(opt.v)"
            >
              {{ opt.l }}
            </button>
          </div>
          <p class="mt-2 text-[11px] leading-snug text-n-slate-10">
            通过邮件里的追踪像素统计打开次数与来源地区；部分邮箱（如
            Gmail）会代理图片加载，打开信息仅供参考。
          </p>
        </template>
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
                      v-for="f in allFoldersFlat"
                      :key="f.id"
                      class="flex w-full px-3 py-1.5 text-sm text-left whitespace-nowrap hover:bg-n-alpha-1 text-n-slate-12"
                      :style="{ paddingLeft: 12 + f.depth * 14 + 'px' }"
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
              <div class="relative">
                <button
                  class="flex items-center justify-center rounded size-8 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
                  title="打标签"
                  :disabled="bulkBusy"
                  @click="bulkLabelMenuOpen = !bulkLabelMenuOpen"
                >
                  <Icon icon="i-lucide-tag" class="size-5" />
                </button>
                <template v-if="bulkLabelMenuOpen">
                  <div
                    class="fixed inset-0 z-20"
                    @click="bulkLabelMenuOpen = false"
                  />
                  <div
                    class="absolute right-0 z-30 mt-1 py-1 overflow-y-auto border rounded-lg shadow-lg min-w-[150px] max-h-64 border-n-weak bg-n-solid-1"
                  >
                    <button
                      v-for="l in labels"
                      :key="l.id"
                      class="flex items-center w-full gap-2 px-3 py-1.5 text-sm text-left hover:bg-n-alpha-1 text-n-slate-12"
                      @click="bulkAddLabel(l.id)"
                    >
                      <span
                        class="rounded-full size-2 shrink-0"
                        :class="labelDot(l.color)"
                      />
                      <span class="flex-1 truncate">{{ l.name }}</span>
                    </button>
                    <div
                      v-if="!labels.length"
                      class="px-3 py-1.5 text-xs text-n-slate-10"
                    >
                      暂无标签
                    </div>
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

          <!-- 「往来邮件」客户过滤条：显示当前只看某客户的收发件记录，可一键清除 -->
          <div
            v-if="customerFilter"
            class="flex items-center gap-2 px-4 py-2 text-xs border-b border-n-weak bg-n-iris-2 text-n-slate-11"
          >
            <Icon icon="i-lucide-mails" class="size-3.5 text-n-iris-11" />
            <span class="truncate">
              只看
              <span class="font-semibold text-n-slate-12">{{
                customerFilter.name
              }}</span>
              的往来邮件（收 + 发）
            </span>
            <button
              class="flex items-center gap-1 px-2 py-0.5 ml-auto rounded text-n-slate-11 hover:bg-n-alpha-2"
              @click="clearCustomerFilter"
            >
              <Icon icon="i-lucide-x" class="size-3" />
              返回
            </button>
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
                  class="flex items-center justify-center flex-shrink-0 text-sm font-medium transition-transform rounded-full cursor-pointer size-9 hover:ring-2 hover:ring-n-iris-8 hover:ring-offset-1"
                  :class="avatarClass(record)"
                  :data-counterparty="record.counterpartyType || 'unknown'"
                  title="快捷操作：写跟进 / 往来邮件"
                  @click.stop="openAvatarCard(record, $event)"
                >
                  {{ initial(counterpartyLabel(record)) }}
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
                      {{ counterpartyLabel(record) }}
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
                    <span
                      v-if="record._threadCount > 1"
                      class="inline-flex items-center gap-0.5 px-1.5 py-0.5 mr-1 rounded text-[10px] font-semibold align-middle bg-n-iris-3 text-n-iris-11"
                      title="本会话邮件数"
                    >
                      <Icon icon="i-lucide-messages-square" class="size-3" />
                      {{ record._threadCount }}
                    </span>
                    {{ record.subject || '(无主题)' }}
                  </div>
                  <div class="mt-0.5 text-xs truncate text-n-slate-10">
                    {{ stripTextColorMarkers(record.body) || '（无正文）' }}
                  </div>
                  <div class="flex items-center gap-2 mt-1.5">
                    <span
                      v-for="l in emailLabels(record)"
                      :key="`rl-${l.id}`"
                      class="rounded-full size-2 shrink-0"
                      :class="labelDot(l.color)"
                      :title="l.name"
                    />
                    <span
                      v-if="showSendBadge(record)"
                      class="px-1.5 py-0.5 rounded text-[11px] font-medium flex-shrink-0 whitespace-nowrap"
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
                      v-if="record.customerName && record.counterpartyName"
                      class="px-1.5 py-0.5 rounded text-[11px] bg-n-alpha-2 text-n-slate-11 truncate max-w-[140px]"
                      :title="counterparty(record)"
                    >
                      {{ record.customerName }}
                    </span>
                    <span
                      v-if="distributionLabel(record)"
                      class="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[11px] bg-n-teal-3 text-n-teal-11 max-w-[150px]"
                      :title="distributionLabel(record).title"
                    >
                      <Icon
                        icon="i-lucide-user-round"
                        class="size-3 shrink-0"
                      />
                      <span class="shrink-0">
                        {{ distributionLabel(record).prefix }}
                      </span>
                      <span class="truncate">
                        {{ distributionLabel(record).name }}
                      </span>
                      <span class="shrink-0">
                        {{ distributionLabel(record).suffix }}
                      </span>
                    </span>
                    <Icon
                      v-if="record.files?.length"
                      icon="i-lucide-paperclip"
                      class="size-3 text-n-slate-10"
                    />
                    <span
                      v-if="
                        record.tracked &&
                        record.openCount &&
                        activeFolder !== 'tracking'
                      "
                      class="inline-flex items-center gap-0.5 text-[11px] text-n-teal-11 flex-shrink-0"
                    >
                      <Icon icon="i-lucide-eye" class="size-3" />
                      {{ record.openCount }}
                    </span>
                  </div>
                  <!-- 追踪视图：打开信息单独一行，避免和状态/客户挤在一起 -->
                  <div
                    v-if="activeFolder === 'tracking'"
                    class="flex items-center gap-3 mt-1 text-[11px] text-n-slate-10"
                  >
                    <span
                      v-if="record.openCount"
                      class="inline-flex items-center gap-1 flex-shrink-0 text-n-teal-11"
                    >
                      <Icon icon="i-lucide-eye" class="size-3" />
                      打开 {{ record.openCount }} 次
                    </span>
                    <span v-else class="flex-shrink-0">未打开</span>
                    <span
                      v-if="trackingLocation(record)"
                      class="inline-flex items-center gap-1 min-w-0 truncate"
                    >
                      <Icon
                        icon="i-lucide-map-pin"
                        class="flex-shrink-0 size-3"
                      />
                      {{ trackingLocation(record) }}
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
                          ? STAR_ON
                          : `text-n-slate-8 ${STAR_HOVER}`
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

    <!-- 右栏：阅读窗格（手机端仅在选中邮件时占满显示）。
         readerRef 给 AI 背调抽屉量左边缘用——抽屉要正好盖住正文区，不切在中间。 -->
    <section
      ref="readerRef"
      class="flex-col flex-1 min-w-0 bg-n-background"
      :class="selectedEmail ? 'flex' : 'hidden md:flex'"
    >
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
          class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between sm:gap-3 flex-shrink-0 px-4 py-3 sm:px-6 border-b border-n-weak"
        >
          <div class="flex items-center min-w-0 gap-2">
            <button
              class="flex items-center justify-center rounded-lg size-8 md:hidden shrink-0 text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-iris-11"
              title="返回列表"
              @click="selectedEmail = null"
            >
              <Icon icon="i-lucide-arrow-left" class="size-4" />
            </button>
            <h2 class="text-base font-medium truncate text-n-slate-12">
              {{ selectedEmail.subject || '(无主题)' }}
            </h2>
            <span
              v-if="showSendBadge(selectedEmail)"
              class="px-2 py-0.5 rounded-full text-xs font-medium flex-shrink-0"
              :class="SEND_STATUSES[selectedEmail.sendStatus]?.class"
            >
              {{ SEND_STATUSES[selectedEmail.sendStatus]?.label }}
            </span>
          </div>
          <div
            class="flex items-center flex-wrap justify-end flex-shrink-0 gap-1"
          >
            <button
              class="flex items-center justify-center rounded-lg size-8 transition-colors hover:bg-n-alpha-1"
              :class="
                selectedEmail.isStarred
                  ? STAR_ON
                  : `text-n-slate-10 ${STAR_HOVER}`
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
            <!-- 标签：给这封邮件打/去标签（勾选切换）+ 新建标签 -->
            <div class="relative">
              <button
                class="flex items-center justify-center transition-colors rounded-lg size-8 text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-iris-11"
                title="标签"
                @click="labelMenuOpen = !labelMenuOpen"
              >
                <Icon icon="i-lucide-tag" class="size-4" />
              </button>
              <template v-if="labelMenuOpen">
                <div
                  class="fixed inset-0 z-40"
                  @click="labelMenuOpen = false"
                />
                <div
                  class="absolute right-0 z-50 py-1 mt-1 overflow-y-auto border rounded-lg shadow-lg top-9 min-w-[160px] max-h-72 border-n-weak bg-n-solid-1"
                >
                  <button
                    v-for="l in labels"
                    :key="l.id"
                    class="flex items-center w-full gap-2 px-3 py-1.5 text-sm text-left hover:bg-n-alpha-1 text-n-slate-12"
                    @click="toggleEmailLabel(selectedEmail, l.id)"
                  >
                    <span
                      class="rounded-full size-2 shrink-0"
                      :class="labelDot(l.color)"
                    />
                    <span class="flex-1 truncate">{{ l.name }}</span>
                    <Icon
                      v-if="(selectedEmail.labelIds || []).includes(l.id)"
                      icon="i-lucide-check"
                      class="size-3.5 text-n-iris-11"
                    />
                  </button>
                  <div
                    v-if="labels.length"
                    class="my-1 border-t border-n-weak"
                  />
                  <button
                    class="flex items-center w-full gap-1 px-3 py-1.5 text-sm text-left text-n-iris-11 hover:bg-n-alpha-1"
                    @click="createLabel"
                  >
                    <Icon icon="i-lucide-plus" class="size-3.5" />新建标签
                  </button>
                </div>
              </template>
            </div>
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
                class="crm-ai"
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

        <div class="flex-1 px-4 py-4 sm:px-6 sm:py-5 overflow-y-auto">
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
                <span
                  v-for="l in emailLabels(selectedEmail)"
                  :key="`lbl-${l.id}`"
                  class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="labelPill(l.color)"
                >
                  {{ l.name }}
                  <button
                    class="hover:opacity-70"
                    title="移除标签"
                    @click="toggleEmailLabel(selectedEmail, l.id)"
                  >
                    <Icon icon="i-lucide-x" class="size-3" />
                  </button>
                </span>
              </div>
            </div>
          </div>

          <!-- 会话往来：同一往来的多封邮件（同客户/同对方 + 主题归一），点选切换 -->
          <div
            v-if="threadEmails.length > 1"
            class="py-3 border-b border-n-weak"
          >
            <button
              class="flex items-center w-full gap-2 text-sm text-n-slate-11 hover:text-n-slate-12"
              @click="threadExpanded = !threadExpanded"
            >
              <Icon
                icon="i-lucide-messages-square"
                class="size-4 text-n-iris-11"
              />
              <span class="font-medium">
                会话往来（{{ threadEmails.length }} 封）
              </span>
              <Icon
                :icon="
                  threadExpanded
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
                class="ml-auto size-4 text-n-slate-10"
              />
            </button>
            <div v-if="threadExpanded" class="flex flex-col mt-2 gap-0.5">
              <button
                v-for="te in threadEmails"
                :key="te.id"
                class="flex items-center gap-2 px-3 py-2 text-left rounded-lg transition-colors"
                :class="
                  te.id === selectedEmail.id
                    ? 'bg-n-iris-2'
                    : 'hover:bg-n-alpha-1'
                "
                @click="selectEmail(te)"
              >
                <Icon
                  :icon="
                    te.folder === 'INBOX'
                      ? 'i-lucide-arrow-down-left'
                      : 'i-lucide-arrow-up-right'
                  "
                  class="size-3.5 shrink-0"
                  :class="
                    te.folder === 'INBOX' ? 'text-n-teal-11' : 'text-n-blue-11'
                  "
                />
                <div class="flex-1 min-w-0">
                  <div class="text-xs truncate text-n-slate-12">
                    {{ counterparty(te) || '—' }}
                  </div>
                  <div class="text-[11px] truncate text-n-slate-10">
                    {{
                      stripTextColorMarkers(te.body) ||
                      te.subject ||
                      '（无正文）'
                    }}
                  </div>
                </div>
                <Icon
                  v-if="te.files?.length"
                  icon="i-lucide-paperclip"
                  class="size-3 shrink-0 text-n-slate-10"
                  :title="`${te.files.length} 个附件`"
                />
                <span class="text-[11px] tabular-nums text-n-slate-10 shrink-0">
                  {{ relTime(te.emailDate) }}
                </span>
              </button>
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
              <span class="inline-flex items-center gap-1.5 font-medium">
                <Icon
                  icon="i-lucide-mouse-pointer-click"
                  class="size-4"
                  :class="
                    selectedEmail.clickCount
                      ? 'text-n-iris-11'
                      : 'text-n-slate-10'
                  "
                />
                <span
                  :class="
                    selectedEmail.clickCount
                      ? 'text-n-iris-11'
                      : 'text-n-slate-10'
                  "
                >
                  {{
                    selectedEmail.clickCount
                      ? `点击 · ${selectedEmail.clickCount} 次`
                      : '未点击'
                  }}
                </span>
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

          <!-- 附件（置于正文上方，收发邮件都无需拉到底即可看到并预览/下载） -->
          <div v-if="selectedEmail.files?.length" class="mt-5">
            <p
              class="flex items-center gap-2 mb-2.5 text-sm font-medium text-n-slate-11"
            >
              <Icon
                icon="i-lucide-paperclip"
                class="size-4 shrink-0 text-n-iris-11"
              />
              {{
                t('CRM.EMAILS.READING.ATTACHMENTS', {
                  count: selectedEmail.files.length,
                })
              }}
            </p>
            <div class="flex flex-col gap-2">
              <div
                v-for="file in selectedEmail.files"
                :key="file.id"
                class="flex items-center gap-3 p-3 border rounded-lg border-n-weak"
              >
                <img
                  v-if="isImageFile(file)"
                  :src="file.url"
                  :alt="file.filename"
                  class="flex-shrink-0 object-cover transition-opacity rounded cursor-pointer size-10 bg-n-alpha-2 hover:opacity-80"
                  @click="openPreview(file)"
                />
                <span
                  v-else
                  class="grid flex-shrink-0 rounded size-10 place-items-center bg-n-iris-3 text-n-iris-11"
                >
                  <Icon :icon="fileIcon(file)" class="size-5" />
                </span>
                <div class="flex-1 min-w-0">
                  <p
                    class="text-sm truncate text-n-slate-12"
                    :title="file.filename"
                  >
                    {{ file.filename }}
                  </p>
                  <p class="text-xs text-n-slate-10">
                    {{ fmtSize(file.byteSize) }}
                  </p>
                </div>
                <div class="flex items-center flex-shrink-0 gap-1">
                  <button
                    v-if="canPreview(file)"
                    type="button"
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-iris-11 hover:bg-n-iris-3"
                    @click="openPreview(file)"
                  >
                    <Icon icon="i-lucide-eye" class="size-3.5" />
                    预览
                  </button>
                  <a
                    :href="file.url"
                    download
                    target="_blank"
                    rel="noopener noreferrer"
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                  >
                    <Icon icon="i-lucide-download" class="size-3.5" />
                    下载
                  </a>
                </div>
              </div>
            </div>
          </div>

          <!-- 本会话全部附件：整串往来的附件拉平一处，免得为了找一个文件一封封点开 -->
          <div v-if="hasOtherThreadFiles" class="mt-4">
            <button
              type="button"
              class="flex items-center w-full gap-2 text-sm transition-colors text-n-slate-11 hover:text-n-slate-12"
              @click="threadFilesExpanded = !threadFilesExpanded"
            >
              <Icon
                icon="i-lucide-paperclip"
                class="size-4 shrink-0 text-n-iris-11"
              />
              <span class="font-medium">
                本会话全部附件（{{ threadFiles.length }}）
              </span>
              <Icon
                :icon="
                  threadFilesExpanded
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
                class="ml-auto size-4"
              />
            </button>
            <div v-if="threadFilesExpanded" class="flex flex-col gap-2 mt-2.5">
              <div
                v-for="f in threadFiles"
                :key="`${f.emailId}-${f.id}`"
                class="flex items-center gap-3 p-3 border rounded-lg"
                :class="
                  f.emailId === selectedEmail.id
                    ? 'border-n-iris-6'
                    : 'border-n-weak'
                "
              >
                <img
                  v-if="isImageFile(f)"
                  :src="f.url"
                  :alt="f.filename"
                  class="flex-shrink-0 object-cover transition-opacity rounded cursor-pointer size-10 bg-n-alpha-2 hover:opacity-80"
                  @click="openPreview(f)"
                />
                <span
                  v-else
                  class="grid flex-shrink-0 rounded size-10 place-items-center bg-n-iris-3 text-n-iris-11"
                >
                  <Icon :icon="fileIcon(f)" class="size-5" />
                </span>
                <div class="flex-1 min-w-0">
                  <p
                    class="text-sm truncate text-n-slate-12"
                    :title="f.filename"
                  >
                    {{ f.filename }}
                  </p>
                  <p
                    class="flex items-center gap-1.5 text-xs text-n-slate-10 min-w-0"
                  >
                    <Icon
                      :icon="
                        f.inbound
                          ? 'i-lucide-arrow-down-left'
                          : 'i-lucide-arrow-up-right'
                      "
                      class="size-3 shrink-0"
                      :class="f.inbound ? 'text-n-teal-11' : 'text-n-blue-11'"
                    />
                    <button
                      type="button"
                      class="truncate transition-colors hover:text-n-iris-11"
                      title="跳到这封邮件"
                      @click="jumpToThreadEmail(f.emailId)"
                    >
                      {{
                        f.emailId === selectedEmail.id
                          ? '本封'
                          : relTime(f.emailDate)
                      }}
                    </button>
                    <span class="shrink-0">· {{ fmtSize(f.byteSize) }}</span>
                  </p>
                </div>
                <div class="flex items-center flex-shrink-0 gap-1">
                  <button
                    v-if="canPreview(f)"
                    type="button"
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-iris-11 hover:bg-n-iris-3"
                    @click="openPreview(f)"
                  >
                    <Icon icon="i-lucide-eye" class="size-3.5" />
                    预览
                  </button>
                  <a
                    :href="f.url"
                    download
                    target="_blank"
                    rel="noopener noreferrer"
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                  >
                    <Icon icon="i-lucide-download" class="size-3.5" />
                    下载
                  </a>
                </div>
              </div>
            </div>
          </div>

          <!-- 正文（置于附件下方） -->
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
        </div>
      </template>
    </section>

    <!-- 邮件分发弹窗 -->
    <div
      v-if="distributeDialog"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
      @click.self="distributeDialog = false"
    >
      <div
        class="w-full max-w-[440px] max-h-[90vh] overflow-auto p-5 border rounded-2xl bg-n-solid-1 shadow-xl border-n-weak"
      >
        <div class="flex items-center justify-between mb-1">
          <h3 class="text-base font-semibold text-n-slate-12">分发给同事</h3>
          <button
            class="grid rounded-lg size-7 place-items-center text-n-slate-10 hover:bg-n-alpha-2"
            @click="distributeDialog = false"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <p class="mb-3 text-xs text-n-slate-10">
          把这封邮件（含正文和附件）分发给公司内部同事查看 · 站内流转不外发
        </p>
        <div
          class="p-2.5 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 truncate"
        >
          {{ distributeEmail?.subject || '(无主题)' }}
        </div>

        <div v-if="distributions.length" class="mb-3">
          <div class="mb-1 text-xs text-n-slate-10">已分发记录</div>
          <div class="flex flex-col gap-1 overflow-auto max-h-24">
            <div
              v-for="d in distributions"
              :key="d.id"
              class="flex items-center justify-between text-xs text-n-slate-11"
            >
              <span class="truncate">
                {{ d.from_user_name }} → {{ d.to_user_name }}
                <span v-if="d.note" class="text-n-slate-9"
                  >（{{ d.note }}）</span
                >
              </span>
              <span class="text-n-slate-9 shrink-0">{{
                (d.created_at || '').slice(0, 10)
              }}</span>
            </div>
          </div>
        </div>

        <div class="mb-1.5 text-xs text-n-slate-10">选择同事</div>
        <div v-if="distributeIds.length" class="flex flex-wrap gap-1.5 mb-2">
          <span
            v-for="m in distMembers.filter(x => distributeIds.includes(x.id))"
            :key="m.id"
            class="inline-flex items-center gap-1 py-1 pl-2.5 pr-1.5 text-xs text-white rounded-full bg-n-iris-9"
          >
            {{ m.name }}
            <button
              type="button"
              class="grid rounded-full size-4 place-items-center hover:bg-white/20"
              @click="toggleDistId(m.id)"
            >
              <Icon icon="i-lucide-x" class="size-3" />
            </button>
          </span>
        </div>
        <input
          v-model="distributeQuery"
          type="text"
          placeholder="搜索同事…"
          class="w-full px-3 py-2 mb-1 text-sm border rounded-lg outline-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
        />
        <div
          class="flex flex-col gap-0.5 mb-3 overflow-auto border rounded-lg max-h-40 border-n-weak"
        >
          <button
            v-for="m in distributeMembers"
            :key="m.id"
            type="button"
            class="flex items-center justify-between px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-2"
            @click="toggleDistId(m.id)"
          >
            <span class="truncate">{{ m.name }}</span>
            <Icon
              v-if="distributeIds.includes(m.id)"
              icon="i-lucide-check"
              class="size-4 text-n-iris-11 shrink-0"
            />
          </button>
          <div
            v-if="!distributeMembers.length"
            class="px-3 py-2 text-xs text-n-slate-9"
          >
            无匹配同事
          </div>
        </div>

        <textarea
          v-model="distributeNote"
          rows="2"
          placeholder="附言（可空）"
          class="w-full px-3 py-2 mb-4 text-sm border rounded-lg outline-none resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-iris-7"
        />

        <div class="flex justify-end gap-2">
          <button
            class="px-4 py-2 text-sm font-medium rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="distributeDialog = false"
          >
            取消
          </button>
          <button
            class="px-4 py-2 text-sm font-semibold text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-60"
            :disabled="distributing"
            @click="submitDistribute"
          >
            {{ distributing ? '分发中…' : '分发' }}
          </button>
        </div>
      </div>
    </div>

    <!-- 头像快捷卡：点邮件头像弹出，写跟进 / 往来邮件 -->
    <Teleport to="body">
      <template v-if="avatarCard">
        <div class="fixed inset-0 z-[60]" @click="closeAvatarCard" />
        <div
          class="fixed z-[61] w-56 py-2 border rounded-xl shadow-xl border-n-weak bg-n-solid-1"
          :style="{ top: avatarCard.top + 'px', left: avatarCard.left + 'px' }"
        >
          <div class="px-3 pb-2 mb-1 border-b border-n-weak">
            <div class="text-sm font-semibold truncate text-n-slate-12">
              {{
                avatarCard.record.customerName ||
                counterparty(avatarCard.record)
              }}
            </div>
            <div class="text-xs truncate text-n-slate-10">
              {{ counterparty(avatarCard.record) }}
            </div>
          </div>
          <template v-if="avatarCard.record.crmCustomerId">
            <button
              class="flex items-center w-full gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="cardWriteFollowUp"
            >
              <Icon icon="i-lucide-pencil-line" class="size-4 text-n-iris-11" />
              写跟进
            </button>
            <button
              class="flex items-center w-full gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
              @click="cardShowCorrespondence"
            >
              <Icon icon="i-lucide-mails" class="size-4 text-n-iris-11" />
              往来邮件（收 + 发）
            </button>
          </template>
          <div v-else class="px-3 py-2 text-xs text-n-slate-10">
            该邮箱尚未建档为客户
          </div>
          <button
            class="flex items-center w-full gap-2 px-3 py-2 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="openBackgroundCheck(avatarCard.record)"
          >
            <Icon icon="i-lucide-search-check" class="size-4 text-n-iris-11" />
            AI 背调
          </button>
        </div>
      </template>
    </Teleport>

    <!-- AI 背调右侧抽屉：对这封邮件的「对方」查公司底细，结果可直接写回客户档案 -->
    <Teleport to="body">
      <template v-if="bgDrawer">
        <div
          class="fixed inset-0 z-[70] bg-black/20"
          @click="closeBackgroundCheck"
        />
        <div
          class="fixed top-0 right-0 z-[71] flex flex-col w-full h-full overflow-hidden border shadow-2xl rounded-2xl bg-n-solid-1 border-n-weak"
          :style="bgDrawerStyle"
        >
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <div class="min-w-0">
              <div class="text-sm font-semibold text-n-slate-12">AI 背调</div>
              <div class="text-xs truncate text-n-slate-10">
                {{ bgDrawer.name || bgDrawer.address }}
                <template v-if="bgDrawer.name">
                  · {{ bgDrawer.address }}
                </template>
              </div>
            </div>
            <button
              class="flex items-center justify-center rounded size-8 text-n-slate-10 hover:bg-n-alpha-2"
              @click="closeBackgroundCheck"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>
          <div class="flex-1 p-5 overflow-y-auto">
            <CrmBackgroundCheck
              ref="bgPanelRef"
              :email="bgDrawer.address"
              :name="bgDrawer.name"
              :import-label="
                bgDrawer.record.crmCustomerId
                  ? bgSaving
                    ? '写入中…'
                    : '写入客户档案'
                  : '用这些信息建档'
              "
              :import-hint="
                bgDrawer.record.crmCustomerId
                  ? '只补档案里还空着的字段，概况追加到备注，不覆盖你填过的内容'
                  : '该邮箱还没建档：带着这些信息打开建档表单，建完自动挂上往来邮件'
              "
              @apply="applyBackgroundToCustomer"
            />
          </div>
        </div>
      </template>
    </Teleport>

    <!-- 背调后建档：复用客户建档弹窗，预填背调结果 + 这封邮件的对方地址 -->
    <CrmCustomerCreateDialog
      ref="bgDialogRef"
      @create="createCustomerFromBackground"
    />

    <!-- 写跟进右侧抽屉：不跳转，直接记一条跟进 -->
    <Teleport to="body">
      <template v-if="followUpDrawer">
        <div class="fixed inset-0 z-[70] bg-black/20" @click="closeFollowUp" />
        <div
          class="fixed top-0 right-0 z-[71] flex flex-col w-full h-full max-w-md border-l shadow-2xl bg-n-solid-1 border-n-weak"
        >
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <div class="min-w-0">
              <div class="text-sm font-semibold text-n-slate-12">写跟进</div>
              <div class="text-xs truncate text-n-slate-10">
                {{ followUpDrawer.customerName }}
              </div>
            </div>
            <button
              class="flex items-center justify-center rounded size-8 text-n-slate-10 hover:bg-n-alpha-2"
              @click="closeFollowUp"
            >
              <Icon icon="i-lucide-x" class="size-4" />
            </button>
          </div>
          <div class="flex-1 p-5 overflow-y-auto">
            <textarea
              v-model="followUpText"
              rows="8"
              placeholder="记录这次跟进的内容、结果、下一步…"
              class="w-full px-3 py-2 text-sm border rounded-lg resize-none no-margin border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-iris-9"
            />
          </div>
          <div
            class="flex items-center justify-end gap-2 px-5 py-4 border-t border-n-weak"
          >
            <Button label="取消" variant="link" @click="closeFollowUp" />
            <Button
              label="保存跟进"
              color="iris"
              :disabled="!followUpText.trim() || followUpSaving"
              :is-loading="followUpSaving"
              @click="saveFollowUp"
            />
          </div>
        </div>
      </template>
    </Teleport>

    <!-- 附件预览：图片灯箱 / PDF 站内 iframe，无需下载即可查看 -->
    <Teleport to="body">
      <div
        v-if="previewFile"
        class="fixed inset-0 z-[9999] flex flex-col bg-black/80"
        @click.self="closePreview"
      >
        <div
          class="flex items-center justify-between h-14 gap-3 px-4 border-b bg-n-slate-12 border-white/15 shrink-0"
        >
          <span class="text-sm truncate text-white/90">
            {{ previewFile.filename }}
          </span>
          <div class="flex items-center flex-shrink-0 gap-2">
            <a
              :href="previewFile.url"
              download
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1.5 px-3 h-9 text-sm text-white rounded-lg bg-white/15 hover:bg-white/25"
            >
              <Icon icon="i-lucide-download" class="size-4" />
              下载
            </a>
            <button
              type="button"
              class="inline-flex items-center gap-1.5 px-4 h-9 text-sm font-semibold text-n-slate-12 bg-white rounded-lg hover:bg-white/90"
              @click="closePreview"
            >
              <Icon icon="i-lucide-x" class="size-4" />
              关闭
            </button>
          </div>
        </div>
        <div
          class="flex items-center justify-center flex-1 min-h-0 p-4"
          @click.self="closePreview"
        >
          <div v-if="previewLoading" class="text-sm text-white/80">加载中…</div>
          <img
            v-else-if="isImageFile(previewFile) && previewUrl"
            :src="previewUrl"
            :alt="previewFile.filename"
            class="object-contain max-w-full max-h-full rounded shadow-2xl"
          />
          <iframe
            v-else-if="previewUrl"
            :src="previewUrl"
            :title="previewFile.filename"
            class="w-full h-full bg-white rounded"
          />
          <!-- Office 文档转换结果（docx/xlsx）：prose 排版 + 可滚动 -->
          <!-- eslint-disable-next-line vue/no-v-html -->
          <div
            v-else-if="previewHtml"
            class="w-full h-full p-6 overflow-auto prose bg-white rounded prose-sm max-w-none prose-table:text-xs prose-td:border prose-td:border-n-weak prose-td:px-2 prose-td:py-1 prose-th:border prose-th:border-n-weak prose-th:px-2 prose-th:py-1"
            v-html="previewHtml"
          />
        </div>
      </div>
    </Teleport>
  </div>
</template>
