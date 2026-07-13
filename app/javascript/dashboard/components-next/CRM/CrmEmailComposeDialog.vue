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
import camelcaseKeys from 'camelcase-keys';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useCrmEmailsStore } from 'dashboard/stores/crm/emails';
import CrmEmailAPI from 'dashboard/api/crm/emails';
import MailAccountsAPI from 'dashboard/api/crm/mailAccounts';
import EmailTemplatesAPI from 'dashboard/api/crm/emailTemplates';
import CrmCustomerAPI from 'dashboard/api/crm/customers';
import ContactsAPI from 'dashboard/api/crm/contacts';
import KnowledgeDocsAPI from 'dashboard/api/crm/knowledgeDocs';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

const emit = defineEmits(['refresh']);
const store = useCrmEmailsStore();
const { formatMessage } = useMessageFormatter();

// 界面中文文案（CRM 模块为中文，绑定到模板避免 bare-string）。
const L = {
  send: '发送',
  sending: '发送中…',
  draft: '存草稿',
  preview: '预览',
  cancel: '取消',
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
  kbSelect: '从知识库选择',
  kbTip:
    '产品目录、报价单等知识库资料可直接选作附件；选中后复制进本邮件、锁定当前版本。',
  signature: '插入签名…',
  noSignature: '（无签名）',
  applyTemplate: '套用模板',
  noTemplate: '— 不套用 —',
  sentBanner: '已提交发送，结果见邮件列表状态。可继续写下一封。',
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
};

// 富文本编辑器输出 Markdown；发送/预览时用 Chatwoot 的 MessageFormatter 转 HTML。
const markdownToHtml = src => formatMessage(src || '', false, false);

// ---- 状态 ----
const visible = ref(false);
const status = ref({ state: 'idle', msg: '' });
const sending = computed(() => status.value.state === 'sending');

const accounts = ref([]);
const fromId = ref('');
const templates = ref([]);
const templateId = ref('');

const form = reactive({
  to: '',
  cc: '',
  bcc: '',
  subject: '',
  body: '',
});
const showCc = ref(false);
const showBcc = ref(false);

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
  { label: '黑体', value: '"Heiti SC", SimHei, sans-serif' },
  { label: '楷体', value: '"Kaiti SC", KaiTi, serif' },
];
const FONT_SIZES = [
  { label: '正常', value: '' },
  { label: '小', value: '13px' },
  { label: '大', value: '18px' },
  { label: '特大', value: '24px' },
];
const fontFamily = ref('');
const fontSize = ref('');

// 客户 / 联系人
const customerQuery = ref('');
const customerHits = ref([]);
const customer = ref(null);
const contacts = ref([]);
const contactId = ref('');
let customerTimer = null;

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

// 编辑区实时预览用的样式；发送/预览时把同样的字体套在正文外层。
const bodyStyle = computed(() => {
  const style = {};
  if (fontFamily.value) style.fontFamily = fontFamily.value;
  if (fontSize.value) style.fontSize = fontSize.value;
  return style;
});
const bodyHtml = computed(() => {
  const html = markdownToHtml(form.body);
  const parts = [];
  if (fontFamily.value) parts.push(`font-family:${fontFamily.value}`);
  if (fontSize.value) parts.push(`font-size:${fontSize.value}`);
  return parts.length ? `<div style="${parts.join(';')}">${html}</div>` : html;
});

// 字体/字号浮层贴到编辑器工具栏按钮组右侧：运行时量出按钮条位置。
const bodyRef = ref(null);
const toolbarPos = ref(null);
const measureToolbar = () => {
  const root = bodyRef.value;
  const menubar = root?.querySelector('.ProseMirror-menubar');
  if (!menubar) {
    toolbarPos.value = null;
    return;
  }
  const base = root.getBoundingClientRect();
  const bar = menubar.getBoundingClientRect();
  toolbarPos.value = bar.width
    ? { left: bar.right - base.left + 8, top: bar.top - base.top }
    : null;
};
const fontToolbarStyle = computed(() =>
  toolbarPos.value
    ? { left: `${toolbarPos.value.left}px`, top: `${toolbarPos.value.top}px` }
    : { right: '16px', top: '20px' }
);
onMounted(() => window.addEventListener('resize', measureToolbar));
onBeforeUnmount(() => window.removeEventListener('resize', measureToolbar));

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
  if (accounts.value[0]) fromId.value = accounts.value[0].id;
};

const loadTemplates = async () => {
  const { data } = await EmailTemplatesAPI.get();
  templates.value = camelcaseKeys(data.payload || [], { deep: true });
};

const loadKbDocs = async () => {
  const { data } = await KnowledgeDocsAPI.get({ per_page: 200 });
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
  const { data } = await ContactsAPI.get({ customer_id: hit.id });
  const list = camelcaseKeys(data.payload || [], { deep: true }).filter(
    c => c.email
  );
  contacts.value = list;
  if (list[0]) {
    form.to = list[0].email;
    contactId.value = list[0].id;
  }
};

const pickContact = c => {
  contactId.value = c.id;
  form.to = c.email;
};

// ---- 模板 / 签名 ----
const applyTemplate = () => {
  const tpl = templates.value.find(
    x => String(x.id) === String(templateId.value)
  );
  if (!tpl) return;
  if (tpl.subjectTemplate) form.subject = tpl.subjectTemplate;
  form.body = tpl.body || '';
};

const insertSignature = event => {
  const acc = accounts.value.find(a => a.id === Number(event.target.value));
  event.target.value = '';
  if (acc?.signature) {
    form.body = `${form.body}${form.body ? '\n\n' : ''}--\n${acc.signature}`;
  }
};

// ---- 附件 ----
const onPickFiles = event => {
  attachments.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeAttachment = index => attachments.value.splice(index, 1);

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
    toAddress: form.to.trim(),
    ccAddress: showCc.value && form.cc.trim() ? form.cc.trim() : null,
    bccAddress: showBcc.value && form.bcc.trim() ? form.bcc.trim() : null,
    fromAddress: fromAccount.value?.emailAddress || null,
    body: form.body,
    bodyHtml: bodyHtml.value,
    folder: 'DRAFT',
    sendStatus: 'DRAFT',
    crmCustomerId: customer.value?.id || form.crmCustomerId || null,
    contactId: contactId.value || null,
  };
  return attachments.value.length
    ? { ...fields, __files: attachments.value }
    : fields;
};

// 建草稿 → 挂知识库附件（快照）→ 返回 id；发送时再翻 sendNow。
const persist = async () => {
  const record = await store.create(buildFields());
  if (kbPicked.value.length) {
    await CrmEmailAPI.attachKb(
      record.id,
      kbPicked.value.map(k => k.fileId)
    );
  }
  return record.id;
};

const saveDraft = async () => {
  if (!form.to.trim()) {
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

const send = async () => {
  if (!form.to.trim()) {
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
    status.value = { state: 'sent', msg: '' };
    emit('refresh');
  } catch (e) {
    status.value = { state: 'failed', msg: String(e?.message || e) };
  }
};

// ---- 开关 / 复位 ----
const reset = () => {
  form.to = '';
  form.cc = '';
  form.bcc = '';
  form.subject = '';
  form.body = '';
  form.crmCustomerId = null;
  showCc.value = false;
  showBcc.value = false;
  customerQuery.value = '';
  customerHits.value = [];
  customer.value = null;
  contacts.value = [];
  contactId.value = '';
  templateId.value = '';
  fontFamily.value = '';
  fontSize.value = '';
  attachments.value = [];
  kbPicked.value = [];
  showKb.value = false;
  showPreview.value = false;
  status.value = { state: 'idle', msg: '' };
};

const close = () => {
  visible.value = false;
  reset();
};

const open = async prefill => {
  reset();
  await Promise.all([loadAccounts(), loadTemplates(), loadKbDocs()]);
  if (prefill && typeof prefill === 'object') {
    if (prefill.toAddress) form.to = prefill.toAddress;
    if (prefill.ccAddress) {
      form.cc = prefill.ccAddress;
      showCc.value = true;
    }
    if (prefill.subject) form.subject = prefill.subject;
    if (prefill.body) form.body = prefill.body;
    if (prefill.crmCustomerId) form.crmCustomerId = prefill.crmCustomerId;
    if (prefill.contactId) contactId.value = prefill.contactId;
  }
  visible.value = true;
  await nextTick();
  measureToolbar();
  // 编辑器布局稳定后再量一次（首帧菜单栏宽度可能还没定）。
  window.setTimeout(measureToolbar, 60);
};

defineExpose({ open, close });
</script>

<template>
  <div
    v-show="visible"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-black/40"
    @click.self="close"
  >
    <div
      class="flex flex-col w-full max-w-[1080px] h-[calc(100vh-3rem)] max-h-[900px]"
    >
      <div
        class="flex flex-col flex-1 min-h-0 overflow-hidden border shadow-xl rounded-xl border-n-weak bg-n-solid-1"
      >
        <!-- 顶部操作栏 -->
        <div
          class="flex items-center flex-shrink-0 gap-2 px-4 py-2.5 border-b bg-n-alpha-1 border-n-weak"
        >
          <button
            class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-amber-9 hover:bg-n-amber-10 disabled:opacity-60"
            :disabled="sending"
            @click="send"
          >
            {{ sending ? L.sending : L.send }}
          </button>
          <button
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-60"
            :disabled="sending"
            @click="saveDraft"
          >
            {{ L.draft }}
          </button>
          <button
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="showPreview = true"
          >
            {{ L.preview }}
          </button>
          <span class="flex-1" />
          <button
            class="px-4 py-1.5 text-sm rounded-full border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="close"
          >
            {{ L.cancel }}
          </button>
        </div>

        <div
          v-if="!hasAccount"
          class="flex-shrink-0 px-4 py-2 text-xs bg-n-amber-3 text-n-amber-11"
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
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 focus:outline-none focus:ring-0"
            >
              <option v-if="!accounts.length" value="">
                {{ L.noAccountOption }}
              </option>
              <option v-for="a in accounts" :key="a.id" :value="a.id">
                {{ a.emailAddress }}
              </option>
            </select>
          </div>

          <!-- 收件人 -->
          <div
            class="flex items-start px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 pt-2.5 text-[13px] text-n-slate-10">
              {{ L.to }}
            </span>
            <input
              v-model="form.to"
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-0"
              :placeholder="L.toPlaceholder"
            />
            <div class="flex items-center gap-3 pt-2.5">
              <button
                v-if="!showCc"
                class="text-[13px] text-n-amber-11 hover:underline"
                @click="showCc = true"
              >
                {{ L.cc }}
              </button>
              <button
                v-if="!showBcc"
                class="text-[13px] text-n-amber-11 hover:underline"
                @click="showBcc = true"
              >
                {{ L.bcc }}
              </button>
            </div>
          </div>

          <!-- 客户 -->
          <div
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
                  class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-0"
                  :placeholder="L.customerPlaceholder"
                  @input="customer = null"
                />
              </div>
              <div
                v-if="customerHits.length"
                class="absolute z-10 mt-1 overflow-hidden border rounded-lg shadow-lg left-14 right-4 bg-n-solid-1 border-n-weak"
              >
                <button
                  v-for="c in customerHits"
                  :key="c.id"
                  class="block w-full px-3 py-2 text-sm text-left border-b text-n-slate-12 border-n-weak hover:bg-n-alpha-1"
                  @click="pickCustomer(c)"
                >
                  {{ c.name }}
                </button>
              </div>
              <div v-if="contacts.length" class="flex flex-wrap gap-1.5 pb-2">
                <button
                  v-for="c in contacts"
                  :key="c.id"
                  class="px-2 py-1 text-xs border rounded-full"
                  :class="
                    contactId === c.id
                      ? 'border-n-amber-9 text-n-amber-11 bg-n-amber-2'
                      : 'border-n-weak text-n-slate-11'
                  "
                  @click="pickContact(c)"
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
            <input
              v-model="form.cc"
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-0"
              :placeholder="L.ccPlaceholder"
            />
          </div>
          <div
            v-if="showBcc"
            class="flex items-center px-4 border-b border-n-weak min-h-[38px]"
          >
            <span class="w-14 text-[13px] text-n-slate-10">{{ L.bcc }}</span>
            <input
              v-model="form.bcc"
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-0"
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
              class="flex-1 py-2 text-sm bg-transparent border-0 reset-base text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-0"
              :placeholder="L.subjectPlaceholder"
            />
          </div>

          <!-- 正文：所见即所得富文本（加粗/斜体/链接/列表 + 内联插图上传/粘贴） -->
          <div
            ref="bodyRef"
            class="relative flex flex-col flex-1 min-h-[20rem]"
          >
            <!-- 字体 / 字号：贴到编辑器工具栏按钮组右侧，整封生效、实时预览 -->
            <div
              class="absolute z-10 flex items-center gap-0.5"
              :style="fontToolbarStyle"
            >
              <select
                v-model="fontFamily"
                class="h-7 px-1.5 text-xs rounded reset-base bg-transparent border-0 text-n-slate-12 hover:bg-n-alpha-2 focus:outline-none focus:ring-0 w-[124px]"
              >
                <option
                  v-for="f in FONT_FAMILIES"
                  :key="f.label"
                  :value="f.value"
                >
                  {{ f.label }}
                </option>
              </select>
              <select
                v-model="fontSize"
                class="h-7 px-1.5 text-xs rounded reset-base bg-transparent border-0 text-n-slate-12 hover:bg-n-alpha-2 focus:outline-none focus:ring-0"
              >
                <option v-for="s in FONT_SIZES" :key="s.label" :value="s.value">
                  {{ s.label }}
                </option>
              </select>
            </div>
            <div
              class="flex flex-col flex-1 px-3 pt-2 pb-3 crm-email-body"
              :style="bodyStyle"
            >
              <Editor
                v-model="form.body"
                editor-key="crm-email-compose"
                channel-type="Channel::Email"
                :enable-canned-responses="false"
                :show-character-count="false"
                :placeholder="L.bodyPlaceholder"
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
            class="inline-flex items-center flex-shrink-0 gap-1 px-2.5 h-8 text-sm border rounded-lg border-n-amber-9 text-n-amber-11 hover:bg-n-amber-2 disabled:opacity-60"
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
            <span
              v-for="(file, index) in attachments"
              :key="`f${index}`"
              class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-full whitespace-nowrap border-n-weak text-n-slate-11 bg-n-solid-1"
            >
              <Icon icon="i-lucide-file" class="size-3 text-n-amber-11" />
              {{ file.name }}
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
              <Icon icon="i-lucide-file-text" class="size-3 text-n-amber-11" />
              {{ pick.label }}
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeKbPick(pick)"
              >
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
          </div>

          <select
            class="h-8 px-2 text-xs border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0 max-w-[128px] flex-shrink-0"
            @change="insertSignature"
          >
            <option value="">{{ L.signature }}</option>
            <option
              v-for="a in accounts"
              :key="a.id"
              :value="a.id"
              :disabled="!a.signature"
            >
              {{ a.emailAddress }}{{ a.signature ? '' : L.noSignature }}
            </option>
          </select>
          <select
            v-model="templateId"
            class="h-8 px-2 text-xs border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0 max-w-[128px] flex-shrink-0"
            @change="applyTemplate"
          >
            <option value="">{{ L.noTemplate }}</option>
            <option v-for="tp in templates" :key="tp.id" :value="tp.id">
              {{ `[${tp.category}] ${tp.name}` }}
            </option>
          </select>
        </div>
      </div>

      <!-- 状态提示 -->
      <div
        v-if="status.state === 'sent'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-teal-11 border-n-teal-7 bg-n-teal-2"
      >
        {{ L.sentBanner }}
      </div>
      <div
        v-else-if="status.state === 'draft'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-blue-11 border-n-blue-7 bg-n-blue-2"
      >
        {{ L.draftBanner }}
      </div>
      <div
        v-else-if="status.state === 'failed'"
        class="px-3 py-2.5 mt-3 text-sm border rounded-lg text-n-ruby-11 border-n-ruby-7 bg-n-ruby-2"
      >
        {{ status.msg }}
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
          <button class="text-sm text-n-amber-11" @click="showPreview = false">
            {{ L.cancel }}
          </button>
        </div>
        <div
          class="px-4 py-3 text-sm leading-loose border-b text-n-slate-11 border-n-weak"
        >
          <div>{{ L.previewFrom }}{{ fromAccount?.emailAddress || '—' }}</div>
          <div>{{ L.previewTo }}{{ form.to || '—' }}</div>
          <div v-if="showCc && form.cc">{{ L.previewCc }}{{ form.cc }}</div>
          <div>{{ L.previewSubject }}{{ form.subject || '(无主题)' }}</div>
        </div>
        <!-- eslint-disable-next-line vue/no-v-html -->
        <div
          class="px-4 py-4 text-sm leading-relaxed text-n-slate-12"
          v-html="bodyHtml"
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
          <button class="text-sm text-n-amber-11" @click="showKb = false">
            {{ L.kbDone
            }}{{ kbPicked.length ? `（已选 ${kbPicked.length}）` : '' }}
          </button>
        </div>

        <!-- 过滤 -->
        <div class="px-4 py-2.5 border-b bg-n-alpha-1 border-n-weak">
          <input
            v-model="kbSearch"
            class="w-full h-9 px-3 mb-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
            :placeholder="L.kbSearchPlaceholder"
          />
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              v-for="chip in kbScopeChips"
              :key="chip.value"
              class="px-2.5 py-1 text-xs border rounded-full"
              :class="
                kbScope === chip.value
                  ? 'border-n-amber-9 bg-n-amber-9 text-white'
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
                  ? 'border-n-amber-9 bg-n-amber-9 text-white'
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
                  ? 'border-n-amber-9 bg-n-amber-9 text-white'
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
                kbOpenDoc?.id === doc.id ? 'bg-n-amber-2' : 'hover:bg-n-alpha-1'
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
                  class="ml-auto min-w-4 h-4 px-1 text-[11px] text-white rounded-full bg-n-amber-9 inline-flex items-center justify-center"
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
                      ? 'border-n-amber-9 text-n-amber-11 bg-n-amber-2'
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
            class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-n-amber-9 hover:bg-n-amber-10"
            @click="showKb = false"
          >
            {{ L.kbDone }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 让富文本编辑器撑满加高后的写信窗，正文区可大段书写 */
.crm-email-body :deep(.editor-wrapper) {
  flex: 1 1 auto;
  min-height: 0;
}

.crm-email-body :deep(.ProseMirror-woot-style) {
  min-height: 16rem;
  max-height: none;
}
</style>
