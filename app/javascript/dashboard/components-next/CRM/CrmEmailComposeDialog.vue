<script setup>
import {
  computed,
  reactive,
  ref,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';
import { useMapGetter } from 'dashboard/composables/store';
import CrmEmailAPI from 'dashboard/api/crm/emails';
import MailAccountsAPI from 'dashboard/api/crm/mailAccounts';
import EmailTemplatesAPI from 'dashboard/api/crm/emailTemplates';
import QuickTextsAPI from 'dashboard/api/crm/quickTexts';
import EmailSignaturesAPI from 'dashboard/api/crm/emailSignatures';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import ContactsAPI from 'dashboard/api/crm/contacts';
import KnowledgeDocsAPI from 'dashboard/api/crm/knowledgeDocs';
import CrmAiAPI from 'dashboard/api/crm/ai';
import {
  CURATED_ZONES,
  COUNTRY_TZ,
  browserTz,
  zonedWallClockToUtc,
  tzOffsetLabel,
} from 'dashboard/routes/dashboard/crm/helper/scheduleTimezone';
import { useAlert } from 'dashboard/composables';
import { renderTextColorSpans } from 'dashboard/helper/editorTextColor';
import {
  uploadInlineDataUriImages,
  uploadInlineHtmlImages,
} from 'dashboard/helper/uploadHelper';
import { vOnClickOutside } from '@vueuse/components';

import DOMPurify from 'dompurify';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmColorPalette from 'dashboard/components-next/CRM/CrmColorPalette.vue';
import CrmRecipientInput from 'dashboard/components-next/CRM/CrmRecipientInput.vue';

const emit = defineEmits(['refresh']);
const store = useCrmEmailsStore();
const currentUser = useMapGetter('getCurrentUser');
const { formatMessage } = useMessageFormatter();

// 界面中文文案（CRM 模块为中文，绑定到模板避免 bare-string）。
const L = {
  send: '发送',
  sending: '发送中…',
  draft: '存草稿',
  schedule: '定时发送',
  scheduleTzLabel: '对应时区',
  scheduleTimeLabel: '对应时间',
  scheduleConfirm: '确定',
  scheduledBanner:
    '已加入定时发送队列，到点自动发送。可在「草稿箱」查看或删除。',
  needSchedule: '请选择定时时间',
  scheduleFuture: '定时时间需晚于当前时刻',
  preview: '预览',
  cancel: '取消',
  confirmClose:
    '邮件还没发送，关闭会丢失已写内容。确定关闭吗？（可先点「存草稿」）',
  noAccountWarn:
    '还没有发信邮箱，去「邮件中心 → 邮箱账户」新建并填 SMTP 授权码后即可发送。',
  from: '发件人',
  noAccountOption: '（未配置发信邮箱）',
  to: '收件人',
  toPlaceholder: '请选择收件人或输入邮箱（多个用英文逗号分隔）',
  cc: '抄送',
  bcc: '密送',
  ccPlaceholder: '抄送邮箱',
  bccPlaceholder: '密送邮箱（收件人看不到）',
  customer: '客户',
  customerPlaceholder: '搜索客户（可选，自动带出联系人邮箱）',
  subject: '主题',
  subjectPlaceholder: '请输入邮件主题',
  bodyPlaceholder:
    '在此输入正文…选中文字可加粗/斜体/链接，工具栏可插入图片、列表。',
  addAttachment: '加附件',
  existingFile: '草稿已有附件（保留）',
  kbSelect: '从知识库选择',
  kbTip:
    '产品目录、报价单等知识库资料可直接选作附件；选中后复制进本邮件、锁定当前版本。',
  signature: '插入签名…',
  defaultSig: '（默认）',
  noSignature: '不加签名',
  sigStripLabel: '签名',
  sigRemove: '移除',
  applyTemplate: '套用模板',
  noTemplate: '— 不套用 —',
  templateBtn: '模版',
  tplPickTitle: '选择模板',
  tplSearch: '请输入模版名称',
  tplManage: '模版管理',
  tplEmpty: '暂无模板',
  tplNew: '新建模板',
  tplTabPersonal: '个人模板',
  tplTabCompany: '企业模板',
  quickTextBtn: '快速文本',
  qtPickTitle: '选择文本',
  qtSearch: '请搜索标题、正文',
  qtEmpty: '暂无数据，点右下「新建文本」添加',
  qtNew: '新建文本',
  qtNewTitle: '新建文本',
  qtEditTitle: '编辑文本',
  qtHint: '写邮件时可一键把常用片段插入正文；点某条即插入。',
  qtTitleLabel: '标题',
  qtTitlePh: '请输入标题',
  qtBodyLabel: '正文',
  qtBodyPh: '请输入常用片段内容',
  qtSave: '保存',
  qtCancel: '取消',
  qtDelete: '删除',
  sentOk: '✅ 成功发送',
  submittedBanner: '已提交发送，仍在投递中，结果稍后见邮件列表状态。',
  draftBanner: '已存入草稿箱。',
  needTo: '请填写收件人',
  needAccount: '你还没有配置启用的发信邮箱（邮件中心 → 邮箱账户）',
  previewTitle: '预览',
  previewFrom: '发件人：',
  previewTo: '收件人：',
  previewCc: '抄送：',
  previewSubject: '主题：',
  kbTitle: '从知识库选择附件',
  kbDone: '完成',
  kbSearchPlaceholder: '搜索文档名 / 摘要 / 文件名',
  kbCompany: '公司',
  kbPersonal: '我的',
  kbAllCategories: '全部分类',
  kbEmptyNoFiles: '知识库里还没有带文件的文档。',
  kbEmptyNoMatch: '没有匹配的文档，换个搜索词或分类试试。',
  kbPickFilePrompt: '选择左侧一篇文档查看并勾选文件。',
  kbFootTip: '勾选的文件会在发送时复制进本邮件并锁定当前版本。',
  colorApply: '文字颜色（选中文字后点击）',
  colorA: 'A',
  colorPalette: '颜料盘',
  underline: '下划线（选中文字后点击）',
  underlineU: 'U',
  aiButton: 'AI 写信',
  aiTitle: 'AI 写信 / 回信',
  aiPlaceholder:
    '用中文描述要写什么，例如：催客户确认 PI，语气客气点；报 500 台 10.1 寸平板的价格，交期 30 天…',
  aiHint:
    '默认写英文（可在描述里指定其他语言）；生成内容会插到正文最上方，可再修改。',
  aiGenerate: '生成',
  aiGenerating: '生成中…（约 10 秒）',
  aiNeedIntent: '请先描述这封邮件要写什么',
  aiFailed: 'AI 生成失败，请稍后再试',
};

// 富文本编辑器输出 Markdown；发送/预览时用 Chatwoot 的 MessageFormatter 转 HTML。
// 文字颜色标记被 html:false 转义成文本，渲染后按严格格式还原成真 span。
const markdownToHtml = src =>
  renderTextColorSpans(formatMessage(src || '', false, false));

// ---- 状态 ----
const visible = ref(false);
const status = ref({ state: 'idle', msg: '' });
const sending = computed(() => status.value.state === 'sending');

const route = useRoute();
const router = useRouter();

const accounts = ref([]);
const fromId = ref('');
const templates = ref([]);
// —— 模板选择弹窗（点「模版」打开，个人/企业分 tab，仿小满 OKKI）——
const templatePickerOpen = ref(false);
const templateTab = ref('PERSONAL');
const templateSearch = ref('');
const templateCategory = ref('');
const TPL_CATEGORY_LABELS = {
  DEVELOPMENT: '开发信',
  QUOTATION: '报价',
  FOLLOW_UP: '跟进',
  PAYMENT_REMINDER: '催款',
  GREETING: '节日问候',
  OTHER: '其他',
};
const templateCategoryOptions = [
  { value: '', label: '全部模版类型' },
  ...Object.entries(TPL_CATEGORY_LABELS).map(([value, label]) => ({
    value,
    label,
  })),
];
const categoryMenuOpen = ref(false);
const currentCategoryLabel = computed(
  () =>
    templateCategoryOptions.find(o => o.value === templateCategory.value)
      ?.label || templateCategoryOptions[0].label
);
const pickerTemplates = computed(() => {
  const kw = templateSearch.value.trim().toLowerCase();
  return templates.value.filter(
    tp =>
      (tp.scope || 'COMPANY') === templateTab.value &&
      (!templateCategory.value || tp.category === templateCategory.value) &&
      (!kw || (tp.name || '').toLowerCase().includes(kw))
  );
});
// —— 快速文本（个人常用片段，写邮件时一键插入正文）——
const quickTextPickerOpen = ref(false);
const quickTexts = ref([]);
const quickTextSearch = ref('');
const quickTextFormOpen = ref(false);
const quickTextForm = reactive({ id: null, title: '', body: '' });
const filteredQuickTexts = computed(() => {
  const kw = quickTextSearch.value.trim().toLowerCase();
  if (!kw) return quickTexts.value;
  return quickTexts.value.filter(
    q =>
      (q.title || '').toLowerCase().includes(kw) ||
      (q.body || '').toLowerCase().includes(kw)
  );
});

const signatures = ref([]);
// 当前签名以「附加块」形式拼进发出的邮件（不塞进 markdown 编辑器），可切换/移除。
const activeSignatureId = ref('');
const activeSignature = computed(
  () =>
    signatures.value.find(
      s => String(s.id) === String(activeSignatureId.value)
    ) || null
);

const form = reactive({
  to: [],
  cc: [],
  bcc: [],
  subject: '',
  body: '',
});

// 群发单显：非空即进入群发模式（收件人来自客户列表勾选，各自单独发、互不可见）。
const bulkRecipients = ref([]);
const isBulk = computed(() => bulkRecipients.value.length > 0);

// 收件人 chip 数组 <-> 逗号分隔字符串互转（后端仍收发字符串）。
const parseRecipients = str =>
  (str || '')
    .split(/[,;]/)
    .map(s => s.trim())
    .filter(Boolean)
    .map(email => ({ email, name: '', type: 'manual' }));
const joinRecipients = arr => (arr || []).map(r => r.email).join(', ');
const addRecipient = (field, r) => {
  if (form[field].some(x => x.email.toLowerCase() === r.email.toLowerCase())) {
    return;
  }
  form[field] = [...form[field], r];
};
const showCc = ref(false);
const showBcc = ref(false);

// 写信窗口形态（仿 Gmail）：small=右下停靠小窗（无遮罩，可操作背后页面、点别处不关）；
// large=居中放大（带遮罩）；minimized=只留标题栏。
const composeMode = ref('small');
const minimized = ref(false);
const toggleMaximize = () => {
  composeMode.value = composeMode.value === 'large' ? 'small' : 'large';
  minimized.value = false;
  resetDrag();
};
const toggleMinimize = () => {
  minimized.value = !minimized.value;
  resetDrag();
};
const rootClass = computed(() => {
  // 最小化优先：不论大/小窗，都收成右下角标题条（无遮罩、不挡页面）。
  if (minimized.value || composeMode.value !== 'large') {
    return 'fixed bottom-0 right-4 z-50';
  }
  return 'fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-black/40';
});
const cardWrapClass = computed(() => {
  if (minimized.value) {
    return 'flex flex-col w-[360px] max-w-[calc(100vw-2rem)] h-[46px]';
  }
  if (composeMode.value === 'large') {
    return 'flex flex-col w-full max-w-[1080px] h-[calc(100vh-3rem)] max-h-[900px]';
  }
  return 'flex flex-col w-[720px] max-w-[calc(100vw-2rem)] h-[600px] max-h-[80vh]';
});

// ---- 写信窗拖动：拖标题栏移动窗口（业务反馈：窗口挡住原邮件、无法移开看原文）----
const cardRef = ref(null);
const dragOffset = ref({ x: 0, y: 0 });
let dragStart = null;
const dragStyle = computed(() =>
  dragOffset.value.x || dragOffset.value.y
    ? {
        transform: `translate(${dragOffset.value.x}px, ${dragOffset.value.y}px)`,
      }
    : {}
);
const resetDrag = () => {
  dragOffset.value = { x: 0, y: 0 };
};
const onDragMove = e => {
  if (!dragStart) return;
  let x = dragStart.ox + (e.clientX - dragStart.mx);
  let y = dragStart.oy + (e.clientY - dragStart.my);
  // 夹在视口内，始终留住标题栏可抓，避免拖出屏幕后再也点不回来。
  const el = cardRef.value;
  if (el) {
    const r = el.getBoundingClientRect();
    const baseLeft = r.left - dragOffset.value.x;
    const baseTop = r.top - dragOffset.value.y;
    const margin = 48;
    x = Math.min(
      Math.max(x, margin - r.width - baseLeft),
      window.innerWidth - margin - baseLeft
    );
    y = Math.min(Math.max(y, -baseTop), window.innerHeight - margin - baseTop);
  }
  dragOffset.value = { x, y };
};
const stopDrag = () => {
  dragStart = null;
  window.removeEventListener('mousemove', onDragMove);
  window.removeEventListener('mouseup', stopDrag);
};
const startDrag = e => {
  // 只从标题栏空白处起拖；点到按钮/输入等交互元素不触发。
  if (e.button !== 0) return;
  if (e.target.closest('button, input, textarea, a, select, [contenteditable]'))
    return;
  dragStart = {
    mx: e.clientX,
    my: e.clientY,
    ox: dragOffset.value.x,
    oy: dragOffset.value.y,
  };
  window.addEventListener('mousemove', onDragMove);
  window.addEventListener('mouseup', stopDrag);
};

// ---- AI 写信：中文意图 → DeepSeek 生成英文商务邮件，插到正文最上方 ----
const aiOpen = ref(false);
const aiIntent = ref('');
const aiLoading = ref(false);

const generateAi = async () => {
  const intent = aiIntent.value.trim();
  if (!intent) {
    useAlert(L.aiNeedIntent);
    return;
  }
  aiLoading.value = true;
  try {
    const { data } = await CrmAiAPI.compose({
      intent,
      // 回复场景把引用原文（含用户已写内容）一并给模型当上下文。
      original: form.body.trim() || undefined,
    });
    if (data.body) {
      const existing = form.body.replace(/^\n+/, '');
      form.body = existing ? `${data.body}\n\n${existing}` : data.body;
    }
    if (data.subject && !form.subject.trim()) form.subject = data.subject;
    aiOpen.value = false;
  } catch (e) {
    useAlert(e?.response?.data?.message || L.aiFailed);
  } finally {
    aiLoading.value = false;
  }
};

// 正文整封字体 / 字号（对齐 Gmail 的字体、字号下拉）。
const FONT_FAMILIES = [
  { label: '默认字体', value: '' },
  {
    label: '无衬线',
    value:
      'Arial, "Helvetica Neue", Helvetica, "PingFang SC", "Microsoft YaHei", sans-serif',
  },
  {
    label: '衬线',
    value: 'Georgia, "Times New Roman", "Songti SC", SimSun, serif',
  },
  { label: '等宽', value: '"Courier New", Courier, monospace' },
  { label: 'Georgia', value: 'Georgia, serif' },
  { label: 'Verdana', value: 'Verdana, Geneva, sans-serif' },
  { label: 'Tahoma', value: 'Tahoma, Geneva, sans-serif' },
  { label: '宋体', value: '"Songti SC", SimSun, serif' },
  { label: '新宋体', value: 'NSimSun, "Songti SC", SimSun, serif' },
  { label: '黑体', value: '"Heiti SC", SimHei, sans-serif' },
  { label: '楷体', value: '"Kaiti SC", KaiTi, serif' },
  { label: '仿宋', value: 'FangSong, STFangsong, serif' },
  { label: '微软雅黑', value: '"Microsoft YaHei", "PingFang SC", sans-serif' },
  { label: 'Arial', value: 'Arial, Helvetica, sans-serif' },
  {
    label: 'Calibri',
    value: 'Calibri, "Segoe UI", Candara, "Trebuchet MS", Arial, sans-serif',
  },
  { label: 'Times New Roman', value: '"Times New Roman", Times, serif' },
  { label: 'Trebuchet MS', value: '"Trebuchet MS", Helvetica, sans-serif' },
  { label: 'Comic Sans MS', value: '"Comic Sans MS", "Comic Sans", cursive' },
  { label: 'Garamond', value: 'Garamond, Baskerville, serif' },
  { label: 'Courier New', value: '"Courier New", Courier, monospace' },
];
const FONT_SIZES = [
  { label: '正常', value: '' },
  { label: '小', value: '13px' },
  { label: '大', value: '18px' },
  { label: '特大', value: '24px' },
];
const fontFamily = ref('');
const fontSize = ref('');
// 字体/字号：无边框「文字 + 符号」下拉（仿小满，替代原生 select 的框）。
const showFontMenu = ref(false);
const showSizeMenu = ref(false);
const currentFontLabel = computed(
  () =>
    FONT_FAMILIES.find(f => f.value === fontFamily.value)?.label ||
    FONT_FAMILIES[0].label
);
const currentSizeLabel = computed(
  () =>
    FONT_SIZES.find(s => s.value === fontSize.value)?.label ||
    FONT_SIZES[0].label
);

// 选中文字颜色：颜料盘组件（预设色板/最近使用/渐变取色/hex 输入）见 CrmColorPalette。
const editorRef = ref(null);
const textColor = ref('#e53935');
const showColorMenu = ref(false);

const applyTextColor = color => {
  if (color) textColor.value = color;
  editorRef.value?.setTextColor(color);
  showColorMenu.value = false;
};

// 客户 / 联系人
const customerQuery = ref('');
const customerHits = ref([]);
const customer = ref(null);
const contacts = ref([]);
const contactId = ref('');
const customerFocused = ref(false); // 搜索结果只在聚焦时显示，失焦收起，避免下拉盖住「主题」
let customerTimer = null;

// 失焦延迟收起，给结果项的点击留出触发时间。
const blurCustomerSoon = () => {
  setTimeout(() => {
    customerFocused.value = false;
  }, 150);
};
// 定时发送时区（默认用户本地；选中客户后按其国家自动预选）——在 pickCustomer 前声明。
const scheduleTz = ref(browserTz());

// 编辑草稿：非空 = 就地更新该邮件，existingFiles 为草稿已有附件（只读展示）。
const editId = ref(null);
const existingFiles = ref([]);

// 普通附件
const attachments = ref([]);
const fileInputRef = ref(null);

// 知识库附件
const kbDocs = ref([]);
const kbPicked = ref([]);
const showKb = ref(false);
const kbSearch = ref('');
const kbCategory = ref('');
const kbScope = ref('');
const kbOpenDocId = ref(null);

// 预览
const showPreview = ref(false);

const fromAccount = computed(
  () => accounts.value.find(a => a.id === fromId.value) || null
);
const hasAccount = computed(() => accounts.value.length > 0);

// 编辑区实时预览用的样式：用 CSS 变量下发字体/字号（自定义属性会穿透所有中间层，
// 而 font-size:inherit 只取直接父级，编辑器中间包一层带字号会挡住选择 → 字号不生效）。
const bodyStyle = computed(() => {
  const style = {};
  if (fontFamily.value) style['--crm-font-family'] = fontFamily.value;
  if (fontSize.value) style['--crm-font-size'] = fontSize.value;
  return style;
});
// 回复/转发时正文里「原邮件」引用的分隔标记（与 CrmEmailsIndex 的 quotedBody 一致）。
// 签名要插在「回复正文」与「原邮件引用」之间，而不是整封（含引用）最底部。
const QUOTE_MARKER = '------ 原邮件 ------';

// ---- 回复/转发：原邮件富文本引用（保留顾客颜色/加重/内嵌图/表格，只读展示 + 原样带回）----
// 原邮件的 HTML 存在 Crm::Email.body_html，回复时作为独立引用块拼进发出的 HTML，
// 不塞进 markdown 编辑器（markdown schema 会把颜色/表格/图拍平）。
const quoteHtmlRaw = ref(''); // 原邮件 HTML（已 DOMPurify 清洗）
const quotePlain = ref(''); // 原邮件纯文本兜底
const quoteMeta = ref(null); // { from, date, subject }
const showQuote = ref(true); // UI 折叠开关
const escapeHtml = s =>
  String(s ?? '').replace(
    /[&<>]/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]
  );
const quoteHeaderHtml = computed(() => {
  const m = quoteMeta.value;
  if (!m) return QUOTE_MARKER;
  return `${QUOTE_MARKER}<br>发件人：${escapeHtml(m.from || '—')}<br>时间：${escapeHtml(m.date || '')}<br>主题：${escapeHtml(m.subject || '(无主题)')}`;
});
// 发出的 HTML 里的引用块：分隔头 + 原邮件 HTML（灰色引用条样式，收件端习惯）。
const quoteBlockHtml = computed(() =>
  quoteHtmlRaw.value
    ? `<br><br><div style="color:#6b7280;font-size:13px">${quoteHeaderHtml.value}</div>` +
      `<blockquote style="margin:8px 0 0;padding-left:12px;border-left:2px solid #d1d5db">${quoteHtmlRaw.value}</blockquote>`
    : ''
);
const quoteBlockText = computed(() => {
  if (!quoteHtmlRaw.value && !quotePlain.value) return '';
  const m = quoteMeta.value;
  const header = m
    ? `${QUOTE_MARKER}\n发件人：${m.from || '—'}\n时间：${m.date || ''}\n主题：${m.subject || '(无主题)'}`
    : QUOTE_MARKER;
  return `\n\n${header}\n\n${quotePlain.value}`;
});

const fontWrap = html => {
  const parts = [];
  if (fontFamily.value) parts.push(`font-family:${fontFamily.value}`);
  if (fontSize.value) parts.push(`font-size:${fontSize.value}`);
  return parts.length ? `<div style="${parts.join(';')}">${html}</div>` : html;
};
const bodyHtml = computed(() => fontWrap(markdownToHtml(form.body)));

// 签名以富文本块拼在正文之后（HTML 发送用），纯文本兜底拼在 text part。
const signatureHtml = computed(() => {
  const sig = activeSignature.value;
  if (!sig) return '';
  const inner = (
    sig.bodyHtml || (sig.body ? sig.body.replace(/\n/g, '<br>') : '')
  )
    // 剥掉签名自身开头的空行/空段，否则与下面的换行叠加，签名前留一大段空白（业务反馈「间隔太远」）。
    .replace(/^(?:\s|&nbsp;|<br\s*\/?>|<div>\s*<\/div>|<p>\s*<\/p>)+/i, '');
  // 正文与签名之间只留一个换行（正文段落自带下边距已够分隔），避免间隔太远。
  return inner ? `<br>${inner}` : '';
});
// 拼接签名前裁掉正文尾部空白（回复正文末尾常带空行），
// 否则与签名自带的空行叠加，签名前会留一大段空白（用户反馈「间隔好大」）。
const trimTrailing = s => (s || '').replace(/\s+$/, '');
// 发送前把签名 HTML 里的 base64 内联图上传换成 URL 的结果（见 persist）；
// 未清洗时回退到原签名 HTML（用于草稿本地拼接，最终发送以清洗后为准）。
const cleanedSignatureHtml = ref(null);
const composedHtml = computed(() => {
  const sig = cleanedSignatureHtml.value ?? signatureHtml.value;
  const body = form.body || '';
  // 新版回复：原邮件走独立 HTML 引用块（quoteBlockHtml），编辑器里只有回信正文。
  if (quoteBlockHtml.value) {
    const replyHtml = fontWrap(markdownToHtml(trimTrailing(body)));
    return `${replyHtml}${sig}${quoteBlockHtml.value}`;
  }
  // 旧版兼容：引用以文本形式内嵌在 body（草稿等）。
  const idx = body.indexOf(QUOTE_MARKER);
  if (sig && idx !== -1) {
    const replyHtml = markdownToHtml(trimTrailing(body.slice(0, idx)));
    const quotedHtml = markdownToHtml(body.slice(idx));
    return fontWrap(`${replyHtml}${sig}${quotedHtml}`);
  }
  if (sig) return `${fontWrap(markdownToHtml(trimTrailing(body)))}${sig}`;
  return bodyHtml.value;
});
const composedText = computed(() => {
  const sig = activeSignature.value;
  const plain = sig?.body ? `\n\n${sig.body}` : '';
  const body = form.body || '';
  // 新版回复：纯文本兜底 = 回信 + 签名 + 原邮件纯文本引用。
  if (quoteBlockText.value) {
    return `${trimTrailing(body)}${plain}${quoteBlockText.value}`;
  }
  const idx = body.indexOf(QUOTE_MARKER);
  if (plain && idx !== -1) {
    return `${trimTrailing(body.slice(0, idx))}${plain}\n\n${body.slice(idx)}`;
  }
  if (plain) return `${trimTrailing(body)}${plain}`;
  return body;
});

// 字体/颜色/下划线控件贴在编辑器菜单栏（B I <> …）右侧、同一行。
// 关键：用菜单栏「真实中线」对齐（bar.top + bar.height/2），不猜像素；
// 对开窗动画瞬间的脏测量（曾量到 top=-348）做范围保护，量到合理值前不显示。
const bodyRef = ref(null);
const toolbarPos = ref(null); // {left, top}；null=尚未量到合理位置，先隐藏
const measureToolbar = () => {
  const root = bodyRef.value;
  const menubar = root?.querySelector('.ProseMirror-menubar');
  if (!menubar) return;
  const base = root.getBoundingClientRect();
  const bar = menubar.getBoundingClientRect();
  if (!bar.width || !bar.height) return;
  const left = Math.round(bar.right - base.left + 8);
  // 浮层自身 h-7=28px，用 -14 让其竖直中线对齐菜单栏中线。
  const top = Math.round(bar.top + bar.height / 2 - base.top - 14);
  // 只接受合理范围，异常值（动画瞬间/未就绪）直接忽略、等下一次重试。
  if (top < 0 || top > 200 || left < 0 || left + 60 > base.width) return;
  toolbarPos.value = { left, top };
};
const fontToolbarStyle = computed(() =>
  toolbarPos.value
    ? { left: `${toolbarPos.value.left}px`, top: `${toolbarPos.value.top}px` }
    : {}
);
// 打开后编辑器菜单栏布局要几帧才稳定（回复预填正文更晚），轮询重试到量到合理值为止。
let measureTimer = null;
const startMeasuring = () => {
  let tries = 0;
  window.clearInterval(measureTimer);
  measureTimer = window.setInterval(() => {
    measureToolbar();
    tries += 1;
    // 量到位后再多量几次吸收布局微调；~2s 兜底停止。
    if ((toolbarPos.value && tries > 6) || tries > 40) {
      window.clearInterval(measureTimer);
    }
  }, 50);
};
onMounted(() => window.addEventListener('resize', measureToolbar));
onBeforeUnmount(() => {
  window.removeEventListener('resize', measureToolbar);
  window.clearInterval(measureTimer);
});

const kbScopeChips = [
  { value: '', label: '全部' },
  { value: 'COMPANY', label: L.kbCompany },
  { value: 'PERSONAL', label: L.kbPersonal },
];
const kbCategories = computed(() => [
  ...new Set(kbDocs.value.map(d => d.category).filter(Boolean)),
]);

const kbKey = item => `${item.docId}:${item.fileId}`;

const kbFilteredDocs = computed(() => {
  const q = kbSearch.value.trim().toLowerCase();
  return kbDocs.value.filter(d => {
    if (kbScope.value && d.scope !== kbScope.value) return false;
    if (kbCategory.value && d.category !== kbCategory.value) return false;
    if (
      q &&
      !(
        `${d.name} ${d.summary || ''}`.toLowerCase().includes(q) ||
        d.files.some(f => f.filename.toLowerCase().includes(q))
      )
    )
      return false;
    return true;
  });
});
const kbOpenDoc = computed(
  () =>
    kbFilteredDocs.value.find(d => d.id === kbOpenDocId.value) ||
    kbFilteredDocs.value[0] ||
    null
);

// ---- 数据加载 ----
const loadAccounts = async () => {
  const { data } = await MailAccountsAPI.get({ filter: 'mine' });
  accounts.value = camelcaseKeys(data.payload || [], { deep: true }).filter(
    a => a.isActive
  );
  // 默认发件人：优先用户设的默认邮箱，否则取第一个启用邮箱。
  const preferred = accounts.value.find(a => a.isDefault) || accounts.value[0];
  if (preferred) fromId.value = preferred.id;
};

const loadTemplates = async () => {
  const { data } = await EmailTemplatesAPI.get();
  templates.value = camelcaseKeys(data.payload || [], { deep: true });
};

const loadSignatures = async () => {
  const { data } = await EmailSignaturesAPI.get();
  signatures.value = camelcaseKeys(data.payload || [], { deep: true });
};

const loadKbDocs = async () => {
  // 邮件附件只挑销售资料库，避免把内部制度/文档挂给客户。
  const { data } = await KnowledgeDocsAPI.get({
    library: 'SALES',
    per_page: 200,
  });
  kbDocs.value = camelcaseKeys(data.payload || [], { deep: true })
    .map(d => ({
      id: d.id,
      name: d.name || '(未命名)',
      scope: d.scope || 'PERSONAL',
      category: d.category || '',
      summary: d.summary || '',
      files: (d.files || []).map(f => ({
        fileId: f.id,
        filename: f.filename || '(未命名文件)',
      })),
    }))
    .filter(d => d.files.length > 0);
};

// ---- 客户搜索 ----
watch(customerQuery, () => {
  clearTimeout(customerTimer);
  const q = customerQuery.value.trim();
  if (q.length < 2 || customer.value) {
    customerHits.value = [];
    return;
  }
  customerTimer = setTimeout(async () => {
    const { data } = await CrmCustomerAPI.get({ q, page: 1 });
    customerHits.value = camelcaseKeys(data.payload || [], { deep: true });
  }, 350);
});

const pickCustomer = async hit => {
  customer.value = hit;
  customerHits.value = [];
  customerQuery.value = hit.name;
  // 按客户所在国家自动预选定时发送时区（未匹配到则保持当前选择）。
  if (hit.tradeCountry && COUNTRY_TZ[hit.tradeCountry]) {
    scheduleTz.value = COUNTRY_TZ[hit.tradeCountry];
  }
  const { data } = await ContactsAPI.get({ customer_id: hit.id });
  const list = camelcaseKeys(data.payload || [], { deep: true }).filter(
    c => c.email
  );
  contacts.value = list;
  if (list[0]) {
    addRecipient('to', {
      email: list[0].email,
      name: list[0].name || '',
      type: 'contact',
    });
    contactId.value = list[0].id;
  }
};

const pickContact = c => {
  contactId.value = c.id;
  addRecipient('to', { email: c.email, name: c.name || '', type: 'contact' });
};

// ---- 模板 / 签名 ----
const openTemplatePicker = () => {
  templateSearch.value = '';
  templateCategory.value = '';
  templatePickerOpen.value = true;
};
const openTemplateManage = () => {
  const href = router.resolve({
    name: 'crm_email_templates_index',
    params: { accountId: route.params.accountId },
  }).href;
  window.open(href, '_blank'); // 新标签打开，避免丢失当前写信草稿
};
// 邮件模板变量：套模板时按当前客户/联系人/本人替换；未选客户则保留 {{...}} 原样
// （可手改，群发时由后端按每个收件人再填）。支持 {{公司}}/{{客户名}}/{{联系人}}/{{我的名字}}。
const currentContactName = () => {
  const c = contacts.value.find(x => x.id === contactId.value);
  return c?.name || customer.value?.primaryContactName || '';
};
const fillTemplateVars = text => {
  if (!text) return text;
  const company = customer.value?.name || '';
  const contact = currentContactName();
  const me = currentUser.value?.crm_name || currentUser.value?.name || '';
  return text
    .replace(/\{\{\s*(?:公司|客户名|客户)\s*\}\}/g, m => company || m)
    .replace(/\{\{\s*联系人\s*\}\}/g, m => contact || m)
    .replace(/\{\{\s*(?:我的名字|我|发件人)\s*\}\}/g, m => me || m);
};

const applyTemplate = async tpl => {
  if (!tpl) return;
  if (tpl.subjectTemplate) form.subject = fillTemplateVars(tpl.subjectTemplate);
  form.body = fillTemplateVars(tpl.body || '');
  // 模板附件随邮件带出：下载成 File 加进附件列表（走现有上传流）。
  await Promise.all(
    (tpl.files || []).map(async f => {
      try {
        const blob = await (await fetch(f.url)).blob();
        attachments.value.push(
          new File([blob], f.filename, { type: blob.type })
        );
      } catch {
        // 单个附件下载失败不阻断套用
      }
    })
  );
};

const applyTemplateFromPicker = async tpl => {
  await applyTemplate(tpl);
  templatePickerOpen.value = false;
};

// —— 快速文本 ——
const qtAccountId = () => route.params.accountId;
const loadQuickTexts = async () => {
  try {
    const { data } = await QuickTextsAPI.get(qtAccountId());
    quickTexts.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch {
    quickTexts.value = [];
  }
};
const openQuickTextPicker = async () => {
  quickTextSearch.value = '';
  quickTextFormOpen.value = false;
  quickTextPickerOpen.value = true;
  await loadQuickTexts();
};
// 列表预览去掉 HTML 标签只显示纯文本。
const stripHtml = html =>
  String(html || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
// 片段以富文本(HTML)存，插入时直接追加到当前正文末尾。
const insertQuickText = qt => {
  form.body = (form.body || '') + (qt.body || '');
  quickTextPickerOpen.value = false;
};
const openQuickTextCreate = () => {
  quickTextForm.id = null;
  quickTextForm.title = '';
  quickTextForm.body = '';
  quickTextFormOpen.value = true;
};
const openQuickTextEdit = qt => {
  quickTextForm.id = qt.id;
  quickTextForm.title = qt.title || '';
  quickTextForm.body = qt.body || '';
  quickTextFormOpen.value = true;
};
const saveQuickText = async () => {
  if (!quickTextForm.title.trim()) return;
  const payload = {
    title: quickTextForm.title.trim(),
    body: quickTextForm.body,
  };
  try {
    if (quickTextForm.id) {
      await QuickTextsAPI.update(qtAccountId(), quickTextForm.id, payload);
    } else {
      await QuickTextsAPI.create(qtAccountId(), payload);
    }
    quickTextFormOpen.value = false;
    await loadQuickTexts();
  } catch {
    // 保存失败静默（多为标题空）
  }
};
const deleteQuickText = async qt => {
  try {
    await QuickTextsAPI.delete(qtAccountId(), qt.id);
    await loadQuickTexts();
  } catch {
    // ignore
  }
};

// 签名做「附加块」：选一条即设为当前签名（拼到正文后），选「不加签名」则移除。

// ---- 附件 ----
const onPickFiles = event => {
  attachments.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeAttachment = index => attachments.value.splice(index, 1);

// ---- 附件预览：图片灯箱 / PDF 站内 iframe（写信时确认加对了文件）----
const isImgName = n => /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(n || '');
const isPdfName = n => /\.pdf$/i.test(n || '');
// 新加的本地文件（File 对象）
const canPreviewFile = f =>
  (f.type || '').startsWith('image/') ||
  f.type === 'application/pdf' ||
  isImgName(f.name) ||
  isPdfName(f.name);
// 草稿已有附件（带 url）
const canPreviewExisting = f =>
  (f.contentType || '').startsWith('image/') ||
  f.contentType === 'application/pdf' ||
  isImgName(f.filename) ||
  isPdfName(f.filename);

const attPreview = ref(null); // { url, name, isImage, revoke }
const openFilePreview = f => {
  if (!canPreviewFile(f)) return;
  const isImage =
    (f.type || '').startsWith('image/') || isImgName(f.name);
  attPreview.value = {
    url: URL.createObjectURL(f),
    name: f.name,
    isImage,
    revoke: true,
  };
};
const openExistingPreview = f => {
  if (!canPreviewExisting(f)) return;
  const isImage =
    (f.contentType || '').startsWith('image/') || isImgName(f.filename);
  attPreview.value = { url: f.url, name: f.filename, isImage, revoke: false };
};
const closeAttPreview = () => {
  if (attPreview.value?.revoke) URL.revokeObjectURL(attPreview.value.url);
  attPreview.value = null;
};

// ---- 知识库选择器 ----
const openKbPicker = () => {
  showKb.value = true;
  kbOpenDocId.value = null;
  kbSearch.value = '';
  kbCategory.value = '';
  kbScope.value = '';
};
const toggleKbFile = (doc, file) => {
  const item = {
    docId: doc.id,
    docName: doc.name,
    fileId: file.fileId,
    label: file.filename,
  };
  const exists = kbPicked.value.some(p => kbKey(p) === kbKey(item));
  kbPicked.value = exists
    ? kbPicked.value.filter(p => kbKey(p) !== kbKey(item))
    : [...kbPicked.value, item];
};
const removeKbPick = pick => {
  kbPicked.value = kbPicked.value.filter(p => kbKey(p) !== kbKey(pick));
};
const isKbPicked = (docId, fileId) =>
  kbPicked.value.some(p => p.docId === docId && p.fileId === fileId);
const kbPicksForDoc = docId =>
  kbPicked.value.filter(p => p.docId === docId).length;

// ---- 发送 / 存草稿 ----
const buildFields = () => {
  const fields = {
    subject: form.subject.trim() || '(无主题)',
    toAddress: joinRecipients(form.to),
    ccAddress: showCc.value && form.cc.length ? joinRecipients(form.cc) : null,
    bccAddress:
      showBcc.value && form.bcc.length ? joinRecipients(form.bcc) : null,
    fromAddress: fromAccount.value?.emailAddress || null,
    body: composedText.value,
    bodyHtml: composedHtml.value,
    folder: 'DRAFT',
    sendStatus: 'DRAFT',
    crmCustomerId: customer.value?.id || form.crmCustomerId || null,
    contactId: contactId.value || null,
  };
  return attachments.value.length
    ? { ...fields, __files: attachments.value }
    : fields;
};

// 建草稿 / 就地更新草稿 → 挂知识库附件（快照）→ 返回 id；发送时再翻 sendNow。
const persist = async () => {
  // 正文里粘贴进来的 base64 内联图先上传换成短链接，否则会撑爆 body/body_html
  // （文本列上限 2 万字），发送/存草稿直接失败。
  form.body = await uploadInlineDataUriImages(form.body || '');
  // 签名里设计的图片以 base64 内嵌在签名 HTML → 上传换成 URL，否则随邮件发出后
  // 收件端（Gmail 剥离 data: 图 / Outlook 降级成附件）显示不出内联签名图。
  cleanedSignatureHtml.value = await uploadInlineHtmlImages(
    signatureHtml.value
  );
  const { __files: files, ...fields } = buildFields();
  let id;
  if (editId.value) {
    // 编辑草稿：就地更新同一条；有新附件走 multipart（后端 attach 追加，不动已有附件）。
    if (files?.length) {
      const snake = snakecaseKeys(fields, { deep: true });
      const fd = new FormData();
      Object.entries(snake).forEach(([key, value]) => {
        if (value !== null && value !== undefined)
          fd.append(`email[${key}]`, value);
      });
      files.forEach(f => fd.append('email[files][]', f));
      await CrmEmailAPI.updateWithFiles(editId.value, fd);
    } else {
      await store.update({ id: editId.value, ...fields });
    }
    id = editId.value;
  } else {
    const record = await store.create(buildFields());
    id = record.id;
  }
  if (kbPicked.value.length) {
    await CrmEmailAPI.attachKb(
      id,
      kbPicked.value.map(k => k.fileId)
    );
  }
  return id;
};

const saveDraft = async () => {
  if (!form.to.length) {
    status.value = { state: 'failed', msg: L.needTo };
    return;
  }
  status.value = { state: 'sending', msg: '' };
  try {
    await persist();
    status.value = { state: 'draft', msg: '' };
    emit('refresh');
  } catch (e) {
    status.value = { state: 'failed', msg: String(e?.message || e) };
  }
};

// 群发单显：一份正文发给所有勾选客户，后端给每人各建一封独立邮件逐封发（互不可见）。
const bulkSend = async (scheduledIso = null) => {
  if (!hasAccount.value) {
    status.value = { state: 'failed', msg: L.needAccount };
    return;
  }
  status.value = { state: 'sending', msg: '' };
  try {
    // 与单发同款清洗：正文内联图 + 签名内嵌图上传换 URL，避免撑爆列/收件端显示不出。
    form.body = await uploadInlineDataUriImages(form.body || '');
    cleanedSignatureHtml.value = await uploadInlineHtmlImages(
      signatureHtml.value
    );
    const { __files: files, ...fields } = buildFields();
    const snake = snakecaseKeys(fields, { deep: true });
    const fd = new FormData();
    Object.entries(snake).forEach(([key, value]) => {
      if (value !== null && value !== undefined && key !== 'to_address') {
        fd.append(`email[${key}]`, value);
      }
    });
    (files || []).forEach(f => fd.append('email[files][]', f));
    if (scheduledIso) fd.append('email[scheduled_at]', scheduledIso);
    fd.append(
      'recipients',
      JSON.stringify(
        bulkRecipients.value.map(r => ({
          email: r.email,
          crm_customer_id: r.crmCustomerId ?? null,
          contact_id: r.contactId ?? null,
        }))
      )
    );
    const { data } = await CrmEmailAPI.bulkCreate(fd);
    useAlert(
      scheduledIso
        ? `已加入定时群发队列（${data.count} 位客户，到点自动发送，可在「群发箱」查看）`
        : `已群发给 ${data.count} 位客户（发送队列进行中，进度见「群发箱」）`
    );
    visible.value = false;
    reset();
    emit('refresh');
  } catch (e) {
    status.value = {
      state: 'failed',
      msg: e?.response?.data?.error || String(e?.message || e),
    };
  }
};

const send = async () => {
  if (isBulk.value) {
    await bulkSend();
    return;
  }
  if (!form.to.length) {
    status.value = { state: 'failed', msg: L.needTo };
    return;
  }
  if (!hasAccount.value) {
    status.value = { state: 'failed', msg: L.needAccount };
    return;
  }
  status.value = { state: 'sending', msg: '' };
  try {
    const id = await persist();
    await store.update({ id, sendNow: true });
    emit('refresh');
    // 发送是异步的（进队列走 SMTP），轮询真实结果：成功才提示「成功发送」。
    const result = await pollSendResult(id);
    if (result.status === 'FAILED') {
      status.value = {
        state: 'failed',
        msg: result.error || '发送失败，请见邮件列表状态。',
      };
    } else if (result.status === 'SENT') {
      useAlert(L.sentOk);
      visible.value = false;
      reset();
    } else {
      // 仍在投递中：以 toast 告知，弹窗直接关闭（结果去邮件列表看），不再停留需手动关。
      useAlert(L.submittedBanner);
      visible.value = false;
      reset();
    }
    emit('refresh');
  } catch (e) {
    status.value = {
      state: 'failed',
      msg: e?.response?.data?.error || String(e?.message || e),
    };
  }
};

// 轮询单封邮件的发送结果：SENT/FAILED 即返回，约 12 秒仍在发送则返回 PENDING。
const pollSendResult = async id => {
  for (let i = 0; i < 8; i += 1) {
    // eslint-disable-next-line no-await-in-loop, no-promise-executor-return
    await new Promise(resolve => setTimeout(resolve, 1500));
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await CrmEmailAPI.show(id);
      const st = data?.send_status || data?.sendStatus;
      if (st === 'SENT' || st === 'FAILED') {
        return { status: st, error: data?.send_error || data?.sendError };
      }
    } catch {
      // 单次查询失败忽略，继续轮询
    }
  }
  return { status: 'PENDING' };
};

// ---- 定时发送 ----
const showSchedule = ref(false);
const scheduleAt = ref('');
// scheduleTz 已在上方（pickCustomer 之前）声明；此处按“选中时区的当地钟面”解释定时。
const tzOptions = computed(() =>
  CURATED_ZONES.map(z => ({
    value: z.value,
    label: `${z.region}（${tzOffsetLabel(z.value)}）`,
  }))
);
// datetime-local 需要 'YYYY-MM-DDTHH:mm'；最小可选=所选时区当前钟面 +1 分钟（与输入解释口径一致）。
const minScheduleAt = computed(() => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: scheduleTz.value,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
    .formatToParts(new Date(Date.now() + 60000))
    .reduce((a, x) => {
      a[x.type] = x.value;
      return a;
    }, {});
  const hour = parts.hour === '24' ? '00' : parts.hour;
  return `${parts.year}-${parts.month}-${parts.day}T${hour}:${parts.minute}`;
});
// 换算后对应用户本地时间的提示，方便判断“对方这个点你这边几点”。
const scheduleLocalHint = computed(() => {
  if (!scheduleAt.value) return '';
  const when = zonedWallClockToUtc(scheduleAt.value, scheduleTz.value);
  if (Number.isNaN(when.getTime())) return '';
  const local = when.toLocaleString('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  return `= 你本地 ${local}`;
});

const scheduleSend = async () => {
  if (!isBulk.value && !form.to.length) {
    status.value = { state: 'failed', msg: L.needTo };
    return;
  }
  if (!hasAccount.value) {
    status.value = { state: 'failed', msg: L.needAccount };
    return;
  }
  if (!scheduleAt.value) {
    status.value = { state: 'failed', msg: L.needSchedule };
    return;
  }
  const when = zonedWallClockToUtc(scheduleAt.value, scheduleTz.value);
  if (Number.isNaN(when.getTime()) || when.getTime() <= Date.now()) {
    status.value = { state: 'failed', msg: L.scheduleFuture };
    return;
  }
  // 群发模式：定时群发——各客户各建一封 SCHEDULED，到点由后端 job 逐封发。
  if (isBulk.value) {
    showSchedule.value = false;
    await bulkSend(when.toISOString());
    return;
  }
  status.value = { state: 'sending', msg: '' };
  try {
    const id = await persist();
    await store.update({
      id,
      sendStatus: 'SCHEDULED',
      scheduledAt: when.toISOString(),
    });
    showSchedule.value = false;
    status.value = { state: 'scheduled', msg: '' };
    emit('refresh');
  } catch (e) {
    status.value = { state: 'failed', msg: String(e?.message || e) };
  }
};

// ---- 开关 / 复位 ----
const reset = () => {
  form.to = [];
  form.cc = [];
  form.bcc = [];
  form.subject = '';
  form.body = '';
  form.crmCustomerId = null;
  showCc.value = false;
  showBcc.value = false;
  minimized.value = false;
  resetDrag();
  quoteHtmlRaw.value = '';
  quotePlain.value = '';
  quoteMeta.value = null;
  showQuote.value = true;
  customerQuery.value = '';
  customerHits.value = [];
  customer.value = null;
  contacts.value = [];
  contactId.value = '';
  activeSignatureId.value = '';
  cleanedSignatureHtml.value = null;
  editId.value = null;
  existingFiles.value = [];
  fontFamily.value = '';
  fontSize.value = '';
  attachments.value = [];
  kbPicked.value = [];
  showKb.value = false;
  showPreview.value = false;
  showSchedule.value = false;
  scheduleAt.value = '';
  scheduleTz.value = browserTz();
  status.value = { state: 'idle', msg: '' };
  bulkRecipients.value = [];
};

// 有内容则算「脏」——关闭前提醒，避免写好的邮件误关丢失。
const isDirty = () =>
  !!(
    form.to.length ||
    form.cc.length ||
    form.bcc.length ||
    form.subject.trim() ||
    form.body.trim() ||
    attachments.value.length
  );

const close = () => {
  // eslint-disable-next-line no-alert
  if (isDirty() && !window.confirm(L.confirmClose)) return;
  visible.value = false;
  reset();
};

const open = async prefill => {
  reset();
  await Promise.all([
    loadAccounts(),
    loadTemplates(),
    loadKbDocs(),
    loadSignatures(),
  ]);
  if (prefill && typeof prefill === 'object') {
    if (prefill.bulkRecipients?.length) {
      bulkRecipients.value = prefill.bulkRecipients;
    }
    if (prefill.editId) editId.value = prefill.editId;
    if (prefill.files) existingFiles.value = prefill.files;
    // 预置附件（如「作为附件转发」把原邮件 .eml 作为附件带入）。
    if (prefill.attachmentFiles?.length) {
      attachments.value = [...prefill.attachmentFiles];
    }
    if (prefill.toAddress) form.to = parseRecipients(prefill.toAddress);
    if (prefill.ccAddress) {
      form.cc = parseRecipients(prefill.ccAddress);
      showCc.value = true;
    }
    if (prefill.bccAddress) {
      form.bcc = parseRecipients(prefill.bccAddress);
      showBcc.value = true;
    }
    if (prefill.subject) form.subject = prefill.subject;
    if (prefill.body) form.body = prefill.body;
    // 回复/转发的原邮件富文本引用（清洗后只读展示 + 原样带回）。
    if (prefill.quoteHtml) {
      quoteHtmlRaw.value = DOMPurify.sanitize(prefill.quoteHtml);
      quotePlain.value = prefill.quotePlain || '';
      quoteMeta.value = prefill.quoteMeta || null;
      showQuote.value = true;
    }
    if (prefill.crmCustomerId) form.crmCustomerId = prefill.crmCustomerId;
    if (prefill.contactId) contactId.value = prefill.contactId;
    // 从客户列表「写邮件」：带客户对象 → 自动带出客户+联系人+收件人。
    if (prefill.customer) await pickCustomer(prefill.customer);
    // 编辑草稿：发件人对齐草稿原邮箱。
    if (prefill.fromAddress) {
      const acc = accounts.value.find(
        a => a.emailAddress === prefill.fromAddress
      );
      if (acc) fromId.value = acc.id;
    }
  }
  // 新写才自动带默认签名；编辑草稿不再叠加（草稿正文已含原签名，避免重复）。
  if (!editId.value) {
    const defaultSig = signatures.value.find(s => s.isDefault);
    if (defaultSig) activeSignatureId.value = defaultSig.id;
  }
  visible.value = true;
  toolbarPos.value = null; // 重开先隐藏，量到合理位置再显示，避免错位闪一下
  await nextTick();
  startMeasuring();
  // 回复/转发：编辑器挂载后把光标定到引用原文上方的空白回复区，免去手动点击回车。
  if (prefill?.focusReplyTop) {
    window.setTimeout(() => editorRef.value?.focusReplyStart(), 80);
  }
};

defineExpose({ open, close });
</script>

<template>
  <!-- 写信窗（仿 Gmail）：small 右下停靠不挡页面、large 居中放大带遮罩；点窗外一律不关闭。 -->
  <div v-show="visible" :class="rootClass">
    <div ref="cardRef" :class="cardWrapClass" :style="dragStyle">
      <div
        class="flex flex-col flex-1 min-h-0 overflow-hidden border shadow-xl rounded-xl border-n-weak bg-n-solid-1"
      >
        <!-- 顶部操作栏（可拖动移动窗口） -->
        <div
          class="flex items-center flex-shrink-0 gap-2 px-4 py-2.5 border-b cursor-move select-none bg-n-alpha-1 border-n-weak"
          @mousedown="startDrag"
        >
          <span
            v-if="minimized"
            class="flex-1 text-sm font-medium truncate cursor-pointer text-n-slate-12"
            :title="L.previewTitle"
            @click="toggleMinimize"
          >
            {{ form.subject || '新邮件' }}
          </span>
          <button
            v-show="!minimized"
            class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
            :disabled="sending"
            @click="send"
          >
            {{
              sending
                ? L.sending
                : isBulk
                  ? `群发 (${bulkRecipients.length})`
                  : L.send
            }}
          </button>
          <button
            v-show="!minimized && !isBulk"
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-60"
            :disabled="sending"
            @click="saveDraft"
          >
            {{ L.draft }}
          </button>
          <button
            v-show="!minimized && (composeMode === 'large' || isBulk)"
            class="px-4 py-1.5 text-sm rounded-full border disabled:opacity-60"
            :class="
              scheduleAt
                ? 'border-n-iris-9 text-n-iris-11 bg-n-iris-3'
                : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-1'
            "
            :disabled="sending"
            @click="showSchedule = true"
          >
            {{ isBulk ? '定时群发' : L.schedule }}
          </button>
          <button
            v-show="composeMode === 'large' && !minimized"
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="showPreview = true"
          >
            {{ L.preview }}
          </button>
          <span class="flex-1" />
          <button
            type="button"
            class="grid p-1.5 rounded-full text-n-slate-11 hover:bg-n-alpha-2 place-items-center"
            :title="minimized ? '还原' : '最小化'"
            @click="toggleMinimize"
          >
            <span
              :class="minimized ? 'i-lucide-chevron-up' : 'i-lucide-minus'"
              class="block size-4"
            />
          </button>
          <button
            v-show="!minimized"
            type="button"
            class="grid p-1.5 rounded-full text-n-slate-11 hover:bg-n-alpha-2 place-items-center"
            :title="composeMode === 'large' ? '还原' : '放大'"
            @click="toggleMaximize"
          >
            <span
              :class="
                composeMode === 'large'
                  ? 'i-lucide-minimize-2'
                  : 'i-lucide-maximize-2'
              "
              class="block size-4"
            />
          </button>
          <button
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="close"
          >
            {{ L.cancel }}
          </button>
        </div>

        <div
          v-if="!hasAccount"
          class="flex-shrink-0 px-4 py-2 text-xs bg-n-iris-3 text-n-iris-11"
        >
          {{ L.noAccountWarn }}
        </div>

        <!-- 可滚动区：收发信息 + 正文 + 附件 -->
        <div class="flex flex-col flex-1 min-h-0 overflow-y-auto">
          <!-- 发件人 -->
          <div
            class="flex items-center px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 text-[13px] text-n-slate-10">{{ L.from }}</span>
            <select
              v-model="fromId"
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 outline-none focus:outline-none focus:ring-0 ltr:!pl-0 rtl:!pr-0"
            >
              <option v-if="!accounts.length" value="">
                {{ L.noAccountOption }}
              </option>
              <option v-for="a in accounts" :key="a.id" :value="a.id">
                {{ a.emailAddress }}
              </option>
            </select>
          </div>

          <!-- 群发单显：收件人来自客户列表勾选，各自单独发、互不可见 -->
          <div
            v-if="isBulk"
            class="flex items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-iris-2"
          >
            <span class="i-lucide-users size-4 text-n-iris-11" />
            <span class="text-[13px] text-n-slate-12 font-medium">
              群发 {{ bulkRecipients.length }} 位客户
            </span>
            <span class="text-xs text-n-slate-10">
              （每人各收到一封独立邮件，互相不可见）
            </span>
          </div>

          <!-- 收件人 -->
          <div
            v-else
            class="flex items-start px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 pt-2.5 text-[13px] text-n-slate-10">
              {{ L.to }}
            </span>
            <CrmRecipientInput
              v-model="form.to"
              class="flex-1 py-1.5"
              :placeholder="L.toPlaceholder"
            />
            <div class="flex items-center gap-3 pt-2.5">
              <button
                v-if="!showCc"
                class="text-[13px] text-n-iris-11 hover:underline"
                @click="showCc = true"
              >
                {{ L.cc }}
              </button>
              <button
                v-if="!showBcc"
                class="text-[13px] text-n-iris-11 hover:underline"
                @click="showBcc = true"
              >
                {{ L.bcc }}
              </button>
            </div>
          </div>

          <!-- 客户（群发时隐藏：客户已由勾选批量确定） -->
          <div
            v-if="!isBulk"
            class="relative flex items-start px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 pt-2.5 text-[13px] text-n-slate-10">
              {{ L.customer }}
            </span>
            <div class="flex-1">
              <div class="flex items-center">
                <Icon
                  icon="i-lucide-search"
                  class="mr-1.5 size-3.5 text-n-slate-9"
                />
                <input
                  v-model="customerQuery"
                  class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:outline-none focus:ring-0"
                  :placeholder="L.customerPlaceholder"
                  @input="customer = null"
                  @focus="customerFocused = true"
                  @blur="blurCustomerSoon"
                />
              </div>
              <div
                v-if="customerFocused && customerHits.length"
                class="absolute z-10 mt-1 overflow-hidden border rounded-lg shadow-lg left-14 right-4 bg-n-solid-1 border-n-weak"
              >
                <button
                  v-for="c in customerHits"
                  :key="c.id"
                  class="block w-full px-3 py-2 text-sm text-left border-b text-n-slate-12 border-n-weak hover:bg-n-alpha-1"
                  @mousedown.prevent="pickCustomer(c)"
                >
                  {{ c.name }}
                </button>
              </div>
              <div
                v-if="customerFocused && contacts.length"
                class="flex flex-wrap gap-1.5 pb-2"
              >
                <button
                  v-for="c in contacts"
                  :key="c.id"
                  class="px-2 py-1 text-xs border rounded-full"
                  :class="
                    contactId === c.id
                      ? 'border-n-iris-9 text-n-iris-11 bg-n-iris-2'
                      : 'border-n-weak text-n-slate-11'
                  "
                  @mousedown.prevent="pickContact(c)"
                >
                  {{ c.name }} · {{ c.email }}
                </button>
              </div>
            </div>
          </div>

          <!-- 抄送 / 密送 -->
          <div
            v-if="showCc"
            class="flex items-center px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 text-[13px] text-n-slate-10">{{ L.cc }}</span>
            <CrmRecipientInput
              v-model="form.cc"
              class="flex-1 py-1.5"
              :placeholder="L.ccPlaceholder"
            />
          </div>
          <div
            v-if="showBcc"
            class="flex items-center px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 text-[13px] text-n-slate-10">{{ L.bcc }}</span>
            <CrmRecipientInput
              v-model="form.bcc"
              class="flex-1 py-1.5"
              :placeholder="L.bccPlaceholder"
            />
          </div>

          <!-- 主题 -->
          <div
            class="flex items-center px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 text-[13px] text-n-slate-10">{{
              L.subject
            }}</span>
            <input
              v-model="form.subject"
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:outline-none focus:ring-0"
              :placeholder="L.subjectPlaceholder"
            />
          </div>

          <!-- 正文：所见即所得富文本（加粗/斜体/链接/列表 + 内联插图上传/粘贴） -->
          <div ref="bodyRef" class="relative flex flex-col">
            <!-- 字体/字号/颜色/下划线：贴在编辑器菜单栏右侧、同一行；
                 位置由菜单栏真实中线量出（见 measureToolbar），量到前先隐藏避免错位闪。 -->
            <div
              v-show="toolbarPos"
              class="absolute z-10 flex items-center gap-0.5 h-7"
              :style="fontToolbarStyle"
            >
              <!-- 下划线：切换选区/后续输入的下划线 -->
              <button
                class="flex items-center justify-center rounded h-7 w-7 shrink-0 hover:bg-n-alpha-2"
                :title="L.underline"
                @mousedown.prevent
                @click="editorRef?.toggleUnderline()"
              >
                <span
                  class="text-[13px] font-semibold underline underline-offset-2 text-n-slate-12"
                >
                  {{ L.underlineU }}
                </span>
              </button>
              <!-- 文字颜色：A 直接套当前色，▾ 展开色板（含清除/自定义取色） -->
              <div
                v-on-click-outside="() => (showColorMenu = false)"
                class="relative flex items-center rounded shrink-0"
              >
                <button
                  class="flex flex-col items-center justify-center h-7 w-7 hover:bg-n-alpha-2"
                  :title="L.colorApply"
                  @mousedown.prevent
                  @click="applyTextColor(textColor)"
                >
                  <span
                    class="text-[13px] font-semibold leading-none text-n-slate-12"
                  >
                    {{ L.colorA }}
                  </span>
                  <span
                    class="w-4 h-[3px] mt-0.5 rounded-sm"
                    :style="{ backgroundColor: textColor }"
                  />
                </button>
                <button
                  class="flex items-center justify-center rounded h-7 w-4 hover:bg-n-alpha-2"
                  :title="L.colorPalette"
                  @mousedown.prevent
                  @click="showColorMenu = !showColorMenu"
                >
                  <span
                    class="block w-4 h-4 i-lucide-chevron-down shrink-0 text-n-slate-11"
                  />
                </button>
                <div
                  v-if="showColorMenu"
                  class="absolute top-8 left-0 z-20 p-2.5 border rounded-lg shadow-lg bg-n-solid-1 border-n-weak"
                >
                  <CrmColorPalette
                    :model-value="textColor"
                    @select="applyTextColor"
                    @clear="applyTextColor(null)"
                  />
                </div>
              </div>
              <!-- 字体：无边框「文字 + 符号」 -->
              <div
                v-on-click-outside="() => (showFontMenu = false)"
                class="relative shrink-0"
              >
                <button
                  class="flex items-center h-7 gap-0.5 px-1.5 text-xs rounded text-n-slate-12 hover:bg-n-alpha-2"
                  @mousedown.prevent
                  @click="showFontMenu = !showFontMenu"
                >
                  {{ currentFontLabel }}
                  <span
                    class="i-lucide-chevron-down size-3.5 text-n-slate-10"
                  />
                </button>
                <div
                  v-if="showFontMenu"
                  class="absolute left-0 z-20 py-1 overflow-y-auto border rounded-lg shadow-lg top-8 max-h-64 min-w-[140px] border-n-weak bg-n-solid-1"
                >
                  <button
                    v-for="f in FONT_FAMILIES"
                    :key="f.label"
                    class="flex w-full px-3 py-1.5 text-xs text-left whitespace-nowrap hover:bg-n-alpha-1"
                    :class="
                      f.value === fontFamily
                        ? 'text-n-blue-11 font-medium'
                        : 'text-n-slate-12'
                    "
                    :style="f.value ? { fontFamily: f.value } : {}"
                    @mousedown.prevent
                    @click="
                      fontFamily = f.value;
                      showFontMenu = false;
                    "
                  >
                    {{ f.label }}
                  </button>
                </div>
              </div>
              <!-- 字号：无边框「文字 + 符号」 -->
              <div
                v-on-click-outside="() => (showSizeMenu = false)"
                class="relative shrink-0"
              >
                <button
                  class="flex items-center h-7 gap-0.5 px-1.5 text-xs rounded text-n-slate-12 hover:bg-n-alpha-2"
                  @mousedown.prevent
                  @click="showSizeMenu = !showSizeMenu"
                >
                  {{ currentSizeLabel }}
                  <span
                    class="i-lucide-chevron-down size-3.5 text-n-slate-10"
                  />
                </button>
                <div
                  v-if="showSizeMenu"
                  class="absolute left-0 z-20 py-1 overflow-y-auto border rounded-lg shadow-lg top-8 max-h-64 min-w-[96px] border-n-weak bg-n-solid-1"
                >
                  <button
                    v-for="s in FONT_SIZES"
                    :key="s.label"
                    class="flex w-full px-3 py-1.5 text-xs text-left whitespace-nowrap hover:bg-n-alpha-1"
                    :class="
                      s.value === fontSize
                        ? 'text-n-blue-11 font-medium'
                        : 'text-n-slate-12'
                    "
                    @mousedown.prevent
                    @click="
                      fontSize = s.value;
                      showSizeMenu = false;
                    "
                  >
                    {{ s.label }}
                  </button>
                </div>
              </div>
            </div>
            <div
              class="flex flex-col px-3 pt-2 pb-3 crm-email-body"
              :style="bodyStyle"
            >
              <Editor
                ref="editorRef"
                v-model="form.body"
                editor-key="crm-email-compose"
                channel-type="Channel::Email"
                enable-text-color
                enable-inline-image-paste
                :enable-canned-responses="false"
                :show-character-count="false"
                :placeholder="L.bodyPlaceholder"
              />
            </div>
          </div>

          <!-- 签名块：接在正文之后，与正文同处白底内容流（发送时一起带出，可从下拉切换/此处移除） -->
          <div v-if="activeSignature" class="px-3 pb-3 bg-n-solid-1">
            <div
              class="flex items-center gap-2 pt-2 mb-1 border-t border-n-weak"
            >
              <Icon icon="i-lucide-pen-line" class="size-3.5 text-n-slate-9" />
              <span class="text-[11px] text-n-slate-9">
                {{ `${L.sigStripLabel}：${activeSignature.name}` }}
              </span>
              <span class="flex-1" />
              <button
                class="text-[11px] text-n-slate-9 hover:text-n-ruby-11"
                @click="activeSignatureId = ''"
              >
                {{ L.sigRemove }}
              </button>
            </div>
            <!-- eslint-disable-next-line vue/no-v-html -->
            <div
              class="crm-sig-strip text-sm text-n-slate-12"
              v-html="signatureHtml"
            />
          </div>

          <!-- 原邮件富文本引用：回复/转发时保留顾客颜色/加重/内嵌图/表格，只读展示，发送原样带回 -->
          <div v-if="quoteHtmlRaw" class="px-3 pb-3 bg-n-solid-1">
            <div
              class="flex items-center gap-2 pt-2 mb-1 border-t border-n-weak"
            >
              <Icon icon="i-lucide-reply" class="size-3.5 text-n-slate-9" />
              <span class="text-[11px] text-n-slate-9">原邮件（保留原格式）</span>
              <span class="flex-1" />
              <button
                class="text-[11px] text-n-slate-9 hover:text-n-slate-11"
                @click="showQuote = !showQuote"
              >
                {{ showQuote ? '隐藏' : '显示' }}
              </button>
            </div>
            <div
              v-if="showQuote"
              class="pl-3 border-l-2 border-n-weak max-h-80 overflow-auto"
            >
              <div
                v-if="quoteMeta"
                class="mb-2 text-[11px] leading-5 text-n-slate-9"
              >
                <div>发件人：{{ quoteMeta.from || '—' }}</div>
                <div>时间：{{ quoteMeta.date || '' }}</div>
                <div>主题：{{ quoteMeta.subject || '(无主题)' }}</div>
              </div>
              <!-- eslint-disable-next-line vue/no-v-html -->
              <div
                class="text-sm crm-quote-preview text-n-slate-12 [&_img]:max-w-full [&_img]:h-auto [&_table]:max-w-full"
                v-html="quoteHtmlRaw"
              />
            </div>
          </div>
        </div>
        <!-- /可滚动区 -->

        <!-- 底部工具栏：一行左右排版（左 附件/知识库 · 中 已选chip 横滚 · 右 签名/模板） -->
        <div
          class="flex items-center flex-shrink-0 gap-2 px-4 py-2 border-t bg-n-alpha-1 border-n-weak"
        >
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onPickFiles"
          />
          <!-- AI 写信：中文说意图，生成英文商务邮件插入正文顶部 -->
          <div
            v-on-click-outside="() => !aiLoading && (aiOpen = false)"
            class="relative flex-shrink-0"
          >
            <button
              class="crm-ai inline-flex items-center flex-shrink-0 gap-1 px-2.5 h-8 text-sm border rounded-lg border-n-iris-9 text-n-iris-11 hover:bg-n-iris-2 disabled:opacity-60"
              :disabled="sending"
              :title="L.aiTitle"
              @click="aiOpen = !aiOpen"
            >
              <Icon icon="i-lucide-sparkle" class="size-4" />
              {{ L.aiButton }}
            </button>
            <div
              v-if="aiOpen"
              class="absolute bottom-10 left-0 z-30 w-[26rem] p-3 border rounded-lg shadow-lg bg-n-solid-1 border-n-weak"
            >
              <p class="mb-2 text-[13px] font-medium text-n-slate-12">
                {{ L.aiTitle }}
              </p>
              <textarea
                v-model="aiIntent"
                rows="3"
                class="w-full px-2.5 py-2 mb-1 text-sm border rounded-lg resize-none reset-base bg-n-alpha-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-n-amber-9"
                :placeholder="L.aiPlaceholder"
                :disabled="aiLoading"
              />
              <p class="mb-2 text-xs leading-relaxed text-n-slate-10">
                {{ L.aiHint }}
              </p>
              <button
                class="inline-flex items-center gap-1.5 px-3 h-8 text-sm font-medium rounded-lg bg-n-amber-9 text-white hover:bg-n-amber-10 disabled:opacity-60"
                :disabled="aiLoading"
                @click="generateAi"
              >
                <Icon
                  :icon="
                    aiLoading ? 'i-lucide-loader-circle' : 'i-lucide-sparkles'
                  "
                  class="size-4"
                  :class="aiLoading ? 'animate-spin' : ''"
                />
                {{ aiLoading ? L.aiGenerating : L.aiGenerate }}
              </button>
            </div>
          </div>
          <button
            class="inline-flex items-center flex-shrink-0 gap-1 px-2.5 h-8 text-sm border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-60"
            :disabled="sending"
            :title="L.addAttachment"
            @click="fileInputRef?.click()"
          >
            <Icon icon="i-lucide-paperclip" class="size-4" />
            {{ L.addAttachment }}
          </button>
          <button
            class="inline-flex items-center flex-shrink-0 gap-1 px-2.5 h-8 text-sm border rounded-lg border-n-iris-9 text-n-iris-11 hover:bg-n-iris-2 disabled:opacity-60"
            :disabled="sending"
            :title="L.kbTip"
            @click="openKbPicker"
          >
            <Icon icon="i-lucide-book-open" class="size-4" />
            {{ L.kbSelect
            }}{{ kbPicked.length ? `（${kbPicked.length}）` : '' }}
          </button>

          <!-- 已选文件：横向滚动，不额外占高 -->
          <div class="flex items-center flex-1 min-w-0 gap-1.5 overflow-x-auto">
            <!-- 编辑草稿：已有附件（只读，随草稿保留） -->
            <span
              v-for="file in existingFiles"
              :key="`e${file.id}`"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-full whitespace-nowrap border-n-weak text-n-slate-10 bg-n-alpha-1"
              :class="
                canPreviewExisting(file)
                  ? 'cursor-pointer hover:bg-n-alpha-2'
                  : ''
              "
              :title="canPreviewExisting(file) ? '点击预览' : L.existingFile"
              @click="openExistingPreview(file)"
            >
              <Icon
                :icon="
                  canPreviewExisting(file)
                    ? 'i-lucide-eye'
                    : 'i-lucide-paperclip'
                "
                class="size-3 text-n-slate-9"
              />
              {{ file.filename }}
            </span>
            <span
              v-for="(file, index) in attachments"
              :key="`f${index}`"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-full whitespace-nowrap border-n-weak text-n-slate-11 bg-n-solid-1"
            >
              <button
                type="button"
                class="inline-flex items-center gap-1"
                :class="canPreviewFile(file) ? 'hover:text-n-iris-11' : ''"
                :title="canPreviewFile(file) ? '点击预览' : ''"
                @click="openFilePreview(file)"
              >
                <Icon
                  :icon="
                    canPreviewFile(file) ? 'i-lucide-eye' : 'i-lucide-file'
                  "
                  class="size-3 text-n-iris-11"
                />
                {{ file.name }}
              </button>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeAttachment(index)"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
            <span
              v-for="pick in kbPicked"
              :key="kbKey(pick)"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-full whitespace-nowrap border-n-weak text-n-slate-11 bg-n-solid-1"
              :title="`来自「${pick.docName}」`"
            >
              <Icon icon="i-lucide-file-text" class="size-3 text-n-iris-11" />
              {{ pick.label }}
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeKbPick(pick)"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
          </div>

          <button
            type="button"
            class="flex items-center flex-shrink-0 h-8 gap-1 px-3 text-xs border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="openTemplatePicker"
          >
            <Icon icon="i-lucide-layout-template" class="size-3.5" />
            {{ L.templateBtn }}
          </button>
          <button
            type="button"
            class="flex items-center flex-shrink-0 h-8 gap-1 px-3 text-xs border rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="openQuickTextPicker"
          >
            <Icon icon="i-lucide-zap" class="size-3.5" />
            {{ L.quickTextBtn }}
          </button>
        </div>
      </div>

      <!-- 状态提示 -->
      <div
        v-if="status.state === 'draft'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-blue-11 border-n-blue-7 bg-n-blue-2"
      >
        {{ L.draftBanner }}
      </div>
      <div
        v-else-if="status.state === 'scheduled'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-iris-11 border-n-iris-7 bg-n-iris-2"
      >
        {{ L.scheduledBanner }}
      </div>
      <div
        v-else-if="status.state === 'failed'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-ruby-11 border-n-ruby-7 bg-n-ruby-2"
      >
        {{ status.msg }}
      </div>
    </div>

    <!-- 定时发送弹窗：选客户时区 + 当地时间，换算成真实发送时刻 -->
    <div
      v-if="showSchedule"
      class="fixed inset-0 z-10 flex items-center justify-center p-4 bg-black/40"
      @click.self="showSchedule = false"
    >
      <div
        class="w-[440px] max-w-[92vw] border shadow-xl rounded-xl border-n-weak bg-n-solid-1"
      >
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak"
        >
          <strong class="text-base text-n-slate-12">{{ L.schedule }}</strong>
          <button
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="showSchedule = false"
          >
            <span class="i-lucide-x text-lg" />
          </button>
        </div>
        <div class="flex flex-col gap-4 px-5 py-4">
          <div class="flex flex-col gap-1.5">
            <span class="text-sm text-n-slate-11">{{ L.scheduleTzLabel }}</span>
            <SelectCard v-model="scheduleTz" :options="tzOptions" block />
          </div>
          <div class="flex flex-col gap-1.5">
            <span class="text-sm text-n-slate-11">{{
              L.scheduleTimeLabel
            }}</span>
            <input
              v-model="scheduleAt"
              type="datetime-local"
              :min="minScheduleAt"
              class="w-full h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 outline-none focus:outline-none focus:ring-0"
            />
            <span v-if="scheduleLocalHint" class="text-xs text-n-slate-11">
              {{ scheduleLocalHint }}
            </span>
          </div>
        </div>
        <div
          class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak"
        >
          <button
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="showSchedule = false"
          >
            {{ L.cancel }}
          </button>
          <button
            class="px-5 py-1.5 text-sm text-white rounded-full bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
            :disabled="sending || !scheduleAt"
            @click="scheduleSend"
          >
            {{ L.scheduleConfirm }}
          </button>
        </div>
      </div>
    </div>

    <!-- 预览弹窗 -->
    <div
      v-if="showPreview"
      class="fixed inset-0 z-10 flex items-center justify-center bg-black/40"
      @click.self="showPreview = false"
    >
      <div
        class="w-[680px] max-w-[92vw] max-h-[86vh] overflow-auto border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div
          class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
        >
          <strong class="text-n-slate-12">{{ L.previewTitle }}</strong>
          <button class="text-sm text-n-iris-11" @click="showPreview = false">
            {{ L.cancel }}
          </button>
        </div>
        <div
          class="px-4 py-3 text-sm leading-loose border-b text-n-slate-11 border-n-weak"
        >
          <div>{{ L.previewFrom }}{{ fromAccount?.emailAddress || '—' }}</div>
          <div>{{ L.previewTo }}{{ joinRecipients(form.to) || '—' }}</div>
          <div v-if="showCc && form.cc.length">
            {{ L.previewCc }}{{ joinRecipients(form.cc) }}
          </div>
          <div>{{ L.previewSubject }}{{ form.subject || '(无主题)' }}</div>
        </div>
        <!-- eslint-disable-next-line vue/no-v-html -->
        <div
          class="px-4 py-4 text-sm leading-relaxed text-n-slate-12"
          v-html="composedHtml"
        />
      </div>
    </div>

    <!-- 知识库选择器 -->
    <div
      v-if="showKb"
      class="fixed inset-0 z-10 flex items-center justify-center bg-black/40"
      @click.self="showKb = false"
    >
      <div
        class="w-[780px] max-w-[94vw] h-[560px] max-h-[88vh] flex flex-col overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div
          class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
        >
          <strong class="text-n-slate-12">{{ L.kbTitle }}</strong>
          <button class="text-sm text-n-iris-11" @click="showKb = false">
            {{ L.kbDone
            }}{{ kbPicked.length ? `（已选 ${kbPicked.length}）` : '' }}
          </button>
        </div>

        <!-- 过滤 -->
        <div class="px-4 py-2.5 border-b bg-n-alpha-1 border-n-weak">
          <input
            v-model="kbSearch"
            class="w-full h-9 px-3 mb-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            :placeholder="L.kbSearchPlaceholder"
          />
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              v-for="chip in kbScopeChips"
              :key="chip.value"
              class="px-2.5 py-1 text-xs border rounded-full"
              :class="
                kbScope === chip.value
                  ? 'border-n-iris-9 bg-n-iris-9 text-white'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="kbScope = chip.value"
            >
              {{ chip.label }}
            </button>
            <span class="w-px h-4 mx-1 bg-n-weak" />
            <button
              class="px-2.5 py-1 text-xs border rounded-full"
              :class="
                kbCategory === ''
                  ? 'border-n-iris-9 bg-n-iris-9 text-white'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="kbCategory = ''"
            >
              {{ L.kbAllCategories }}
            </button>
            <button
              v-for="cat in kbCategories"
              :key="cat"
              class="px-2.5 py-1 text-xs border rounded-full"
              :class="
                kbCategory === cat
                  ? 'border-n-iris-9 bg-n-iris-9 text-white'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="kbCategory = cat"
            >
              {{ cat }}
            </button>
          </div>
        </div>

        <!-- 文档列表 + 文件面板 -->
        <div class="flex flex-1 min-h-0">
          <div
            class="w-[280px] shrink-0 overflow-y-auto border-r border-n-weak"
          >
            <div
              v-if="!kbFilteredDocs.length"
              class="p-3 text-xs text-n-slate-10"
            >
              {{ kbDocs.length ? L.kbEmptyNoMatch : L.kbEmptyNoFiles }}
            </div>
            <button
              v-for="doc in kbFilteredDocs"
              :key="doc.id"
              class="block w-full px-3.5 py-2.5 text-left border-b border-n-weak"
              :class="
                kbOpenDoc?.id === doc.id ? 'bg-n-iris-2' : 'hover:bg-n-alpha-1'
              "
              @click="kbOpenDocId = doc.id"
            >
              <div
                class="flex items-center gap-1.5 text-[13px] text-n-slate-12"
              >
                <Icon
                  :icon="
                    doc.scope === 'COMPANY'
                      ? 'i-lucide-building-2'
                      : 'i-lucide-user'
                  "
                  class="size-3.5 text-n-slate-10"
                />
                <span class="truncate">{{ doc.name }}</span>
                <span
                  v-if="kbPicksForDoc(doc.id)"
                  class="ml-auto min-w-4 h-4 px-1 text-[11px] text-white rounded-full bg-n-iris-9 inline-flex items-center justify-center"
                >
                  {{ kbPicksForDoc(doc.id) }}
                </span>
              </div>
              <div class="mt-0.5 text-[11px] text-n-slate-10">
                {{ `${doc.category || '未分类'} · ${doc.files.length} 个文件` }}
              </div>
            </button>
          </div>

          <div class="flex-1 overflow-y-auto">
            <div v-if="!kbOpenDoc" class="p-3 text-xs text-n-slate-10">
              {{ L.kbPickFilePrompt }}
            </div>
            <template v-else>
              <div
                class="px-3.5 py-2.5 border-b border-n-weak text-[13px] text-n-slate-11"
              >
                {{ kbOpenDoc.name }}
                <div
                  v-if="kbOpenDoc.summary"
                  class="mt-1 text-[11px] leading-relaxed text-n-slate-10"
                >
                  {{ kbOpenDoc.summary }}
                </div>
              </div>
              <div class="flex flex-col gap-1.5 p-3">
                <button
                  v-for="file in kbOpenDoc.files"
                  :key="file.fileId"
                  class="flex items-center gap-2 px-3 py-2 text-[13px] border rounded-lg"
                  :class="
                    isKbPicked(kbOpenDoc.id, file.fileId)
                      ? 'border-n-iris-9 text-n-iris-11 bg-n-iris-2'
                      : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-1'
                  "
                  @click="toggleKbFile(kbOpenDoc, file)"
                >
                  <Icon
                    :icon="
                      isKbPicked(kbOpenDoc.id, file.fileId)
                        ? 'i-lucide-check-square'
                        : 'i-lucide-square'
                    "
                    class="size-4"
                  />
                  <Icon icon="i-lucide-file-text" class="size-4" />
                  {{ file.filename }}
                </button>
              </div>
            </template>
          </div>
        </div>

        <div
          class="flex items-center gap-2 px-4 py-2.5 border-t bg-n-alpha-1 border-n-weak"
        >
          <span class="flex-1 text-xs text-n-slate-10">{{ L.kbFootTip }}</span>
          <button
            class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-iris-9 hover:bg-n-iris-10"
            @click="showKb = false"
          >
            {{ L.kbDone }}
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- 选择模板弹窗（仿小满 OKKI）：点「模版」打开，个人/企业分 tab，点某条即套用 -->
  <Teleport to="body">
    <div
      v-if="templatePickerOpen"
      class="fixed inset-0 z-[70] flex items-center justify-center bg-black/40"
      @click.self="templatePickerOpen = false"
    >
      <div
        class="flex flex-col w-[860px] max-w-[92vw] h-[560px] max-h-[88vh] overflow-hidden shadow-2xl bg-n-solid-1 rounded-2xl"
      >
        <div
          class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
        >
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ L.tplPickTitle }}
          </h3>
          <button
            class="text-n-slate-10 hover:text-n-slate-12"
            @click="templatePickerOpen = false"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <div class="flex gap-6 px-6 border-b border-n-weak">
          <button
            v-for="tab in [
              { value: 'PERSONAL', label: L.tplTabPersonal },
              { value: 'COMPANY', label: L.tplTabCompany },
            ]"
            :key="tab.value"
            class="py-3 -mb-px text-sm font-medium border-b-2"
            :class="
              templateTab === tab.value
                ? 'border-n-blue-9 text-n-blue-11'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="templateTab = tab.value"
          >
            {{ tab.label }}
          </button>
        </div>

        <div class="flex items-center gap-3 px-6 py-3">
          <input
            v-model="templateSearch"
            type="text"
            :placeholder="L.tplSearch"
            class="h-9 px-3 text-sm border rounded-lg reset-base w-56 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
          />
          <!-- 类型筛选：无边框「文字 + 符号」下拉（仿小满，整洁） -->
          <div class="relative">
            <button
              type="button"
              class="flex items-center h-9 gap-1 text-sm text-n-slate-12 hover:text-n-slate-11"
              @click="categoryMenuOpen = !categoryMenuOpen"
            >
              {{ currentCategoryLabel }}
              <span
                class="size-4 text-n-slate-10"
                :class="
                  categoryMenuOpen
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
              />
            </button>
            <template v-if="categoryMenuOpen">
              <div
                class="fixed inset-0 z-[75]"
                @click="categoryMenuOpen = false"
              />
              <div
                class="absolute left-0 z-[80] mt-1 py-1 overflow-hidden border rounded-lg shadow-lg min-w-[140px] border-n-weak bg-n-solid-1"
              >
                <button
                  v-for="opt in templateCategoryOptions"
                  :key="opt.value"
                  type="button"
                  class="flex w-full px-3 py-1.5 text-sm text-left whitespace-nowrap hover:bg-n-alpha-1"
                  :class="
                    opt.value === templateCategory
                      ? 'text-n-blue-11 font-medium'
                      : 'text-n-slate-12'
                  "
                  @click="
                    templateCategory = opt.value;
                    categoryMenuOpen = false;
                  "
                >
                  {{ opt.label }}
                </button>
              </div>
            </template>
          </div>
        </div>

        <div class="flex-1 px-6 pb-4 overflow-y-auto">
          <p v-pre class="mb-3 text-[11px] leading-snug text-n-slate-10">
            提示：模板/正文可用变量 {{ 公司 }} {{ 联系人 }} {{ 我的名字 }}，套用
            / 群发时自动替换成对应客户信息。
          </p>
          <div
            v-if="!pickerTemplates.length"
            class="flex flex-col items-center justify-center h-full gap-3 text-n-slate-10"
          >
            <Icon icon="i-lucide-folder-open" class="size-10 opacity-40" />
            <p class="text-sm">{{ L.tplEmpty }}</p>
            <button
              class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-iris-9 hover:bg-n-iris-10"
              @click="openTemplateManage"
            >
              {{ L.tplNew }}
            </button>
          </div>
          <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2">
            <button
              v-for="tp in pickerTemplates"
              :key="tp.id"
              type="button"
              class="flex flex-col gap-2 p-4 text-left transition-all border rounded-xl border-n-weak bg-n-solid-1 hover:border-n-iris-7 hover:shadow-sm"
              @click="applyTemplateFromPicker(tp)"
            >
              <div class="flex items-center gap-2 min-w-0">
                <span class="font-medium truncate text-n-slate-12">
                  {{ tp.name }}
                </span>
                <span
                  class="px-1.5 py-0.5 rounded-full text-[11px] shrink-0 bg-n-slate-3 text-n-slate-11 ml-auto"
                >
                  {{ TPL_CATEGORY_LABELS[tp.category] || tp.category }}
                </span>
                <span
                  v-if="tp.files && tp.files.length"
                  class="inline-flex items-center gap-0.5 text-[11px] text-n-slate-10 shrink-0"
                >
                  <Icon icon="i-lucide-paperclip" class="size-3" />{{
                    tp.files.length
                  }}
                </span>
              </div>
              <p
                v-if="tp.subjectTemplate"
                class="text-xs truncate text-n-slate-11"
              >
                {{ tp.subjectTemplate }}
              </p>
              <p
                class="text-xs whitespace-pre-wrap line-clamp-3 text-n-slate-10"
              >
                {{ tp.body || '（无正文）' }}
              </p>
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- 快速文本：选择文本弹窗（点某条即插入正文；右下新建/编辑） -->
  <Teleport to="body">
    <div
      v-if="quickTextPickerOpen"
      class="fixed inset-0 z-[70] flex items-center justify-center bg-black/40"
      @click.self="quickTextPickerOpen = false"
    >
      <div
        class="flex flex-col w-[720px] max-w-[92vw] h-[520px] max-h-[86vh] overflow-hidden shadow-2xl bg-n-solid-1 rounded-2xl"
      >
        <div
          class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
        >
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ quickTextFormOpen ? L.qtNewTitle : L.qtPickTitle }}
          </h3>
          <button
            class="text-n-slate-10 hover:text-n-slate-12"
            @click="quickTextPickerOpen = false"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <!-- 列表态 -->
        <template v-if="!quickTextFormOpen">
          <div class="px-6 py-3">
            <input
              v-model="quickTextSearch"
              type="text"
              :placeholder="L.qtSearch"
              class="w-64 h-9 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
            />
          </div>
          <div class="flex-1 px-6 overflow-y-auto">
            <div
              v-if="!filteredQuickTexts.length"
              class="flex flex-col items-center justify-center h-full gap-2 text-n-slate-10"
            >
              <Icon icon="i-lucide-folder-open" class="size-10 opacity-40" />
              <p class="text-sm">{{ L.qtEmpty }}</p>
            </div>
            <div v-else class="flex flex-col gap-2 pb-2">
              <div
                v-for="qt in filteredQuickTexts"
                :key="qt.id"
                class="flex items-start gap-2 p-3 transition-colors border cursor-pointer group rounded-xl border-n-weak hover:border-n-iris-7 hover:bg-n-alpha-1"
                @click="insertQuickText(qt)"
              >
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-n-slate-12">
                    {{ qt.title }}
                  </div>
                  <div class="text-xs line-clamp-2 text-n-slate-10">
                    {{ stripHtml(qt.body) }}
                  </div>
                </div>
                <div
                  class="flex items-center gap-1 opacity-0 shrink-0 group-hover:opacity-100"
                >
                  <button
                    class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                    @click.stop="openQuickTextEdit(qt)"
                  >
                    <Icon icon="i-lucide-pencil" class="size-3.5" />
                  </button>
                  <button
                    class="p-1 rounded text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
                    @click.stop="deleteQuickText(qt)"
                  >
                    <Icon icon="i-lucide-trash-2" class="size-3.5" />
                  </button>
                </div>
              </div>
            </div>
          </div>
          <div
            class="flex items-center px-6 py-3 border-t border-n-weak bg-n-alpha-1"
          >
            <button
              class="inline-flex items-center gap-1 text-sm font-medium text-n-iris-11 hover:text-n-iris-10"
              @click="openQuickTextCreate"
            >
              <Icon icon="i-lucide-plus" class="size-4" />
              {{ L.qtNew }}
            </button>
          </div>
        </template>

        <!-- 新建/编辑态 -->
        <template v-else>
          <div class="flex flex-col flex-1 gap-4 px-6 py-4 overflow-y-auto">
            <div
              class="flex items-center gap-2 px-3 py-2 text-xs rounded-lg bg-n-blue-2 text-n-blue-11"
            >
              <Icon icon="i-lucide-info" class="size-3.5 shrink-0" />
              {{ L.qtHint }}
            </div>
            <div>
              <label class="block mb-1 text-heading-3 text-n-slate-12">
                {{ L.qtTitleLabel }}
              </label>
              <input
                v-model="quickTextForm.title"
                type="text"
                :placeholder="L.qtTitlePh"
                class="w-full h-9 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
              />
            </div>
            <div class="flex flex-col flex-1 min-h-0">
              <label class="block mb-1 text-heading-3 text-n-slate-12">
                {{ L.qtBodyLabel }}
              </label>
              <div
                class="flex-1 overflow-y-auto border rounded-lg reset-base border-n-weak bg-n-solid-1 min-h-[220px] px-3 py-2 crm-email-body"
              >
                <Editor
                  v-model="quickTextForm.body"
                  editor-key="crm-quick-text"
                  channel-type="Channel::Email"
                  enable-text-color
                  :enable-canned-responses="false"
                  :show-character-count="false"
                  :placeholder="L.qtBodyPh"
                />
              </div>
            </div>
          </div>
          <div
            class="flex items-center justify-end gap-2 px-6 py-3 border-t border-n-weak"
          >
            <button
              class="px-4 py-1.5 text-sm border rounded-full border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
              @click="quickTextFormOpen = false"
            >
              {{ L.qtCancel }}
            </button>
            <button
              class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
              :disabled="!quickTextForm.title.trim()"
              @click="saveQuickText"
            >
              {{ L.qtSave }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </Teleport>

  <!-- 附件预览：图片灯箱 / PDF 站内 iframe -->
  <Teleport to="body">
    <div
      v-if="attPreview"
      class="fixed inset-0 z-[10000] flex flex-col bg-black/80"
      @click.self="closeAttPreview"
    >
      <div
        class="flex items-center justify-between h-14 gap-3 px-4 border-b bg-n-slate-12 border-white/15 shrink-0"
      >
        <span class="text-sm truncate text-white/90">{{ attPreview.name }}</span>
        <div class="flex items-center flex-shrink-0 gap-2">
          <a
            :href="attPreview.url"
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
            @click="closeAttPreview"
          >
            <Icon icon="i-lucide-x" class="size-4" />
            关闭
          </button>
        </div>
      </div>
      <div
        class="flex items-center justify-center flex-1 min-h-0 p-4"
        @click.self="closeAttPreview"
      >
        <img
          v-if="attPreview.isImage"
          :src="attPreview.url"
          :alt="attPreview.name"
          class="object-contain max-w-full max-h-full rounded shadow-2xl"
        />
        <iframe
          v-else
          :src="attPreview.url"
          :title="attPreview.name"
          class="w-full h-full bg-white rounded"
        />
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* 让富文本编辑器撑满加高后的写信窗，正文区可大段书写 */
/* 正文走自然文档流：编辑器按内容自动增高（内容多就把签名顶下去、整窗滚动），
   不再用 flex 撑满导致正文过长时溢出压到签名条上。 */
.crm-email-body :deep(.editor-wrapper) {
  min-height: 18rem;
}

.crm-email-body :deep(.ProseMirror-woot-style) {
  min-height: 18rem;
  max-height: none;
}

/* 正文默认排版对齐 Gmail 观感（未选字体时生效）。默认字体/字号放在容器上，
   编辑器 .ProseMirror 用 inherit 跟随——选了字体/字号时由容器的 :style(bodyStyle)
   覆盖并向下继承生效，否则 ProseMirror 自带的 font 会把用户选择盖掉。 */
.crm-email-body {
  font-family: Arial, 'Helvetica Neue', Helvetica, 'PingFang SC',
    'Microsoft YaHei', sans-serif;
  font-size: 14px;
  line-height: 1.6;
}
.crm-email-body :deep(.ProseMirror),
.crm-email-body :deep(.ProseMirror p) {
  font-family: var(
    --crm-font-family,
    Arial,
    'Helvetica Neue',
    Helvetica,
    'PingFang SC',
    'Microsoft YaHei',
    sans-serif
  );
  font-size: var(--crm-font-size, 14px);
  line-height: 1.6;
}

/* 隐藏编辑器内置的 Copilot「Ask」按钮：未配 Captain，是死按钮，且与「AI 写信」重复。
   class 可能加在内层图标，故一并按 title="Copilot" 隐藏整个菜单项。 */
.crm-email-body :deep(.ProseMirror-copilot),
.crm-email-body :deep(.ProseMirror-menuitem:has(.ProseMirror-copilot)),
.crm-email-body :deep([title='Copilot']) {
  display: none !important;
}

/* 签名预览条：约束签名里的图片，链接沿用蓝色下划线 */
.crm-sig-strip :deep(img) {
  max-width: 100%;
  height: auto;
}
.crm-sig-strip :deep(a) {
  color: #2563eb;
  text-decoration: underline;
}
</style>
