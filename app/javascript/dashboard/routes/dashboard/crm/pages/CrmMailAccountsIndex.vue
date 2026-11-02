<script setup>
import { ref, computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCrmMailAccountsStore } from 'dashboard/stores/crm/mailAccounts';
import { useCrmEmailSignaturesStore } from 'dashboard/stores/crm/emailSignatures';
import MailAccountAPI from 'dashboard/api/crm/mailAccounts';
import MailBlocklistAPI from 'dashboard/api/crm/mailBlocklists';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmSignatureEditor from 'dashboard/components-next/CRM/CrmSignatureEditor.vue';
import CrmSignatureGenerator from 'dashboard/components-next/CRM/CrmSignatureGenerator.vue';
import CrmWhatsappWebBinding from 'dashboard/components-next/CRM/CrmWhatsappWebBinding.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useCrmRole } from 'dashboard/composables/useCrmRole';

const { t } = useI18n();
const store = useCrmMailAccountsStore();
const sigStore = useCrmEmailSignaturesStore();
const settingsSection = ref('accounts');
const dialogRef = ref(null);
const sigDialogRef = ref(null);

const currentUser = useMapGetter('getCurrentUser');
const currentAccount = useMapGetter('getCurrentAccount');

// 生成器打开状态 + 自动带出的资料（少打字）。
const showGenerator = ref(false);
const genPrefill = computed(() => ({
  name: currentUser.value?.name || '',
  enName: currentUser.value?.crm_name || '',
  email: records.value?.[0]?.email || currentUser.value?.email || '',
  company: currentAccount.value?.name || '',
}));

const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const signatures = computed(() => sigStore.getRecords);

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
  // 默认邮箱
  defaultTitle: '默认邮箱',
  defaultHint: '在绑定多个邮箱的情况下，发信时默认选择该邮箱。',
  defaultNone: '（不设默认，取第一个启用邮箱）',
  defaultBadge: '默认',
  // 签名库
  sigTitle: '个性签名',
  sigHint: '可建多条签名，写邮件时下拉插入；设为默认的会在新邮件里自动带出。',
  sigNew: '新建签名',
  sigEmpty: '还没有签名，点「新建签名」建一条常用签名。',
  sigNameLabel: '签名名称',
  sigNamePlaceholder: '如：中文签名 / English Signature',
  sigBodyLabel: '签名内容',
  sigBodyPlaceholder:
    '例如：\nAmber Law\nSales Manager\nUnited Touch Technology Co., Ltd.\namber@wintouchgroup.com',
  sigDefaultLabel: '设为默认签名（新邮件自动带出）',
  sigEditTitle: '编辑签名',
  sigCreateTitle: '新建签名',
  sigDeleteConfirm: '确定删除该签名？',
  // 我的 WhatsApp
  blTitle: '收信黑名单',
  blHint:
    '填域名（如 example.com，连子域名一起拦）或完整邮箱（只拦这一个地址）。命中的信不入库，不会再出现在收件箱、搜索和 AI 摘要里。公共邮箱域名和本公司域名不允许拉黑。',
  blPlaceholder: 'example.com 或 sales@example.com',
  blAdd: '拉黑',
  blSuggest: '这几个域名的来信已被全部标成垃圾邮件：',
  blEmpty: '还没有规则。被反复推销的域名填进来，以后他们的信直接收不进来。',
  blRemove: '取消拦截',
  blAddedBy: '添加',
  waTitle: '我的 WhatsApp',
  waHint: '绑定你的个人 WhatsApp 号，客户消息会直接进入 CRM 会话。',
};

const receiveOptions = [
  { value: 'off', label: '不收信（仅发信）' },
  { value: 'imap', label: 'IMAP 收信' },
  { value: 'pop3', label: 'POP3 收信（服务商关了 IMAP 时用）' },
];
const imapSslOptions = [
  { value: 'true', label: 'SSL 加密' },
  { value: 'false', label: '不加密' },
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
  receiveMode: 'off',
  imapHost: '',
  imapPort: '',
  imapSsl: 'true',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);

const resetForm = () => {
  Object.assign(form, {
    name: '',
    emailAddress: '',
    provider: 'TENCENT_EXMAIL',
    smtpHost: '',
    smtpPort: '',
    smtpPassword: '',
    useSsl: 'true',
    receiveMode: 'off',
    imapHost: '',
    imapPort: '',
    imapSsl: 'true',
  });
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  markPristine();
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
    receiveMode: !record.imapEnabled
      ? 'off'
      : record.receiveProtocol === 'POP3'
        ? 'pop3'
        : 'imap',
    imapHost: record.imapHost || '',
    imapPort: record.imapPort ? String(record.imapPort) : '',
    imapSsl: record.imapSsl === false ? 'false' : 'true',
  });
  markPristine();
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
    imapEnabled: form.receiveMode !== 'off',
    receiveProtocol: form.receiveMode === 'pop3' ? 'POP3' : 'IMAP',
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
      useAlert(`${record.name} 发信失败：${smtp.error || '认证失败'}`);
      return;
    }
    const imap = data.imap;
    const imapMsg = imap
      ? imap.ok
        ? '，收信正常'
        : `，但收信失败：${imap.error}`
      : '';
    useAlert(`${record.name} 发信正常${imapMsg}`);
  } catch {
    useAlert(L.error);
  } finally {
    testingId.value = null;
  }
};

// ---- 默认邮箱 ----
// 仅在启用邮箱里选默认；后端在设默认时会自动撤下同人其余默认，故成功后重新拉取。
const activeAccounts = computed(() => records.value.filter(r => r.isActive));
const defaultAccountId = computed(
  () => records.value.find(r => r.isDefault)?.id || ''
);
const defaultAccountOptions = computed(() => [
  { value: '', label: L.defaultNone },
  ...activeAccounts.value.map(a => ({
    value: String(a.id),
    label: `${a.name}（${a.emailAddress}）`,
  })),
]);
const setDefaultAccount = async value => {
  const id = value ? Number(value) : null;
  try {
    if (id) {
      await store.update({ id, isDefault: true });
    } else {
      const current = records.value.find(r => r.isDefault);
      if (current) await store.update({ id: current.id, isDefault: false });
    }
    await store.get();
  } catch {
    useAlert(L.error);
  }
};

// ---- 签名库 ----
const sigEditingId = ref(null);
const sigForm = reactive({
  name: '',
  body: '',
  bodyHtml: '',
  isDefault: false,
});
const { isDirty: isSigDirty, markPristine: markSigPristine } = useDirtyGuard(
  () => sigForm
);

const openSigCreate = () => {
  sigEditingId.value = null;
  Object.assign(sigForm, {
    name: '',
    body: '',
    bodyHtml: '',
    isDefault: !signatures.value.length,
  });
  markSigPristine();
  sigDialogRef.value?.open();
};

const openSigEdit = record => {
  sigEditingId.value = record.id;
  Object.assign(sigForm, {
    name: record.name || '',
    body: record.body || '',
    // 旧的纯文本签名没有 HTML，回退用纯文本（换行转 <br>）填充富文本编辑器。
    bodyHtml:
      record.bodyHtml ||
      (record.body ? record.body.replace(/\n/g, '<br>') : ''),
    isDefault: !!record.isDefault,
  });
  markSigPristine();
  sigDialogRef.value?.open();
};

const handleSigConfirm = async () => {
  if (!sigForm.name.trim()) return;
  const payload = {
    name: sigForm.name.trim(),
    body: sigForm.body,
    bodyHtml: sigForm.bodyHtml,
    isDefault: sigForm.isDefault,
  };
  try {
    if (sigEditingId.value) {
      await sigStore.update({ id: sigEditingId.value, ...payload });
    } else {
      await sigStore.create(payload);
    }
    // 设默认会撤下同人其余默认，重新拉取以同步显示。
    await sigStore.get();
    sigDialogRef.value?.close();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeSignature = async () => {
  // eslint-disable-next-line no-alert
  if (!sigEditingId.value || !window.confirm(L.sigDeleteConfirm)) return;
  try {
    await sigStore.delete(sigEditingId.value);
    sigDialogRef.value?.close();
    useAlert(L.deleted);
  } catch {
    useAlert(L.error);
  }
};

// 生成器：把生成的 HTML 存成一条签名。
const handleGeneratorSave = async payload => {
  try {
    await sigStore.create(payload);
    await sigStore.get();
    showGenerator.value = false;
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

// ---- 收信黑名单 ----
// 「标记垃圾邮件」只挪那一封、不留记忆，同一家下周再发照样进收件箱。
// 这里的规则在**入库前**丢弃；拦截数和最近一封都记着，拉错了看得见、删得掉。
const { isAdmin, isCrmDeputyAdmin } = useCrmRole();
const canManageBlocklist = computed(
  () => isAdmin.value || isCrmDeputyAdmin.value
);
const blockRules = ref([]);
const blockSuggestions = ref([]);
const blockInput = ref('');
const blockBusy = ref(false);
const blockAccountId = computed(() => currentAccount.value?.id);

const loadBlocklist = async () => {
  if (!canManageBlocklist.value || !blockAccountId.value) return;
  try {
    const { data } = await MailBlocklistAPI.get(blockAccountId.value);
    blockRules.value = data.payload || [];
    blockSuggestions.value = data.suggestions || [];
  } catch {
    // 设置页其余部分照常用，这里静默失败即可
  }
};

const addBlockRule = async value => {
  const v = (value ?? blockInput.value).trim();
  if (!v || blockBusy.value) return;
  blockBusy.value = true;
  try {
    const { data } = await MailBlocklistAPI.create(blockAccountId.value, v);
    blockInput.value = '';
    const swept = data.swept || 0;
    useAlert(
      swept
        ? `已拉黑 ${v}，收件箱里 ${swept} 封同源邮件已移入垃圾箱`
        : `已拉黑 ${v}`
    );
    await loadBlocklist();
  } catch (error) {
    useAlert(error.message || '拉黑失败');
  } finally {
    blockBusy.value = false;
  }
};

const removeBlockRule = async rule => {
  const ok = window.confirm(
    `不再拦截 ${rule.value}？以后这个发件方的信会照常进收件箱。`
  );
  if (!ok) return;
  try {
    await MailBlocklistAPI.delete(blockAccountId.value, rule.id);
    await loadBlocklist();
  } catch (error) {
    useAlert(error.message || '删除失败');
  }
};

const blockHitText = rule => {
  if (!rule.blocked_count) return '还没拦到过';
  if (!rule.last_blocked_subject) return `已拦 ${rule.blocked_count} 封`;
  return `已拦 ${rule.blocked_count} 封，最近一封「${rule.last_blocked_subject}」`;
};

onMounted(() => {
  store.get();
  sigStore.get();
  loadBlocklist();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-white rounded-3xl border border-white/50"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak bg-white [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="min-w-0">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('CRM.MAIL_ACCOUNTS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-10">
          {{ t('CRM.MAIL_ACCOUNTS.HINT') }}
        </p>
      </div>
      <Button
        v-if="settingsSection === 'accounts'"
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        @click="openCreate"
      />
    </div>

    <div class="shrink-0 border-b border-n-weak px-4 sm:px-8">
      <div data-tabbar="page" class="!my-2 inline-flex">
        <button :aria-selected="settingsSection === 'accounts'" @click="settingsSection = 'accounts'">邮箱账户</button>
        <button :aria-selected="settingsSection === 'signatures'" @click="settingsSection = 'signatures'">{{ L.sigTitle }}</button>
        <button :aria-selected="settingsSection === 'whatsapp'" @click="settingsSection = 'whatsapp'">WhatsApp</button>
        <button v-if="canManageBlocklist" :aria-selected="settingsSection === 'blocklist'" @click="settingsSection = 'blocklist'">{{ L.blTitle }}</button>
      </div>
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto p-4 sm:p-6">
      <div class="mx-auto w-full max-w-[1100px]">
      <section v-show="settingsSection === 'accounts'" class="bg-white py-2">
      <div v-if="isFetching" class="p-8 text-sm text-center text-n-slate-11">
        {{ t('CRM.EMAILS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="p-8 text-sm text-center text-n-slate-11"
      >
        {{ L.empty }}
      </div>
      <template v-else>
        <!-- 默认邮箱：多邮箱时发信默认选中的那个 -->
        <div class="mb-5">
          <div
            class="flex flex-col gap-1.5 sm:flex-row sm:items-center sm:gap-3"
          >
            <label
              class="text-sm font-medium text-n-slate-12 sm:w-20 sm:flex-shrink-0"
            >
              {{ L.defaultTitle }}
            </label>
            <div class="flex-1 w-full max-w-md">
              <SelectCard
                block
                class="w-full"
                :model-value="String(defaultAccountId)"
                :options="defaultAccountOptions"
                @update:model-value="setDefaultAccount"
              />
            </div>
          </div>
          <p class="mt-1.5 text-xs text-n-slate-10 sm:pl-[92px]">
            {{ L.defaultHint }}
          </p>
        </div>

        <div class="overflow-hidden rounded-xl border border-n-weak">
          <div
            v-for="record in records"
            :key="record.id"
            class="group flex flex-col gap-3 border-b border-n-weak p-4 last:border-b-0 sm:flex-row sm:items-center sm:justify-between hover:bg-n-alpha-1 cursor-pointer"
            @click="openEdit(record)"
          >
            <div class="flex min-w-0 flex-1 items-center gap-3">
              <div
                class="flex items-center justify-center flex-shrink-0 rounded-lg size-9 bg-[#f1f2f4] text-[#62666f]"
              >
                <Icon icon="i-lucide-mail" class="size-4" />
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-1.5">
                  <h3 class="font-medium truncate text-n-slate-12">
                    {{ record.name }}
                  </h3>
                  <span
                    v-if="record.isDefault"
                    class="px-1.5 py-0.5 rounded text-[10px] flex-shrink-0 bg-n-iris-9 text-white"
                  >
                    {{ L.defaultBadge }}
                  </span>
                </div>
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
            <div class="flex shrink-0 items-center justify-between gap-6 sm:pl-6">
              <button
                class="inline-flex items-center gap-1.5"
                @click.stop="toggleActive(record)"
              >
                <span
                  class="relative w-8 h-4 rounded-full transition-colors"
                  :class="record.isActive ? 'bg-[#303238]' : 'bg-n-slate-5'"
                >
                  <span
                    class="absolute top-0.5 size-3 rounded-full bg-white transition-all"
                    :class="record.isActive ? 'left-4' : 'left-0.5'"
                  />
                </span>
                <span
                  class="text-xs"
                  :class="
                    record.isActive ? 'text-n-slate-11' : 'text-n-slate-10'
                  "
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
      </template>
      </section>

      <!-- 个性签名库 -->
      <div v-show="settingsSection === 'signatures'" class="min-w-0 bg-white py-2">
        <div
          class="flex flex-col gap-3 mb-5 sm:flex-row sm:items-start sm:justify-between"
        >
          <div class="min-w-0">
            <h2 class="text-heading-2 text-n-slate-12">
              {{ L.sigTitle }}
            </h2>
            <p class="mt-0.5 text-xs text-n-slate-10">{{ L.sigHint }}</p>
          </div>
          <div class="flex shrink-0 flex-wrap items-center gap-2">
            <Button
              label="用模板生成"
              icon="i-lucide-wand-sparkles"
              size="sm"
              variant="outline"
              color="slate"
              @click="showGenerator = true"
            />
            <Button
              :label="L.sigNew"
              icon="i-lucide-plus"
              size="sm"
              variant="outline"
              color="slate"
              @click="openSigCreate"
            />
          </div>
        </div>
        <div
          v-if="!signatures.length"
          class="p-6 text-sm text-center text-n-slate-11"
        >
          {{ L.sigEmpty }}
        </div>
        <div
          v-else
          class="grid grid-cols-1 gap-4 lg:grid-cols-2"
        >
          <div
            v-for="sig in signatures"
            :key="sig.id"
            class="flex flex-col gap-2 p-4 transition-shadow border cursor-pointer rounded-2xl border-n-weak bg-n-solid-1 hover:shadow-sm hover:border-n-slate-7"
            @click="openSigEdit(sig)"
          >
            <div class="flex items-center gap-1.5">
              <Icon icon="i-lucide-pen-line" class="size-3.5 text-n-iris-11" />
              <h3 class="font-medium truncate text-n-slate-12">
                {{ sig.name }}
              </h3>
              <span
                v-if="sig.isDefault"
                class="px-1.5 py-0.5 rounded text-[10px] flex-shrink-0 bg-n-iris-9 text-white"
              >
                {{ L.defaultBadge }}
              </span>
            </div>
            <!-- eslint-disable-next-line vue/no-v-html -->
            <div
              v-if="sig.bodyHtml"
              class="crm-sig-preview text-[11px] max-h-24 overflow-hidden text-n-slate-10"
              v-html="sig.bodyHtml"
            />
            <p
              v-else
              class="text-[11px] whitespace-pre-line line-clamp-4 text-n-slate-10"
            >
              {{ sig.body }}
            </p>
          </div>
        </div>
      </div>

      <!-- 我的 WhatsApp -->
      <div v-show="settingsSection === 'whatsapp'" class="min-w-0 bg-white py-2 [&_.grid]:!grid-cols-1 md:[&_.grid]:!grid-cols-2">
        <div class="mb-3 min-w-0">
          <h2 class="text-heading-2 text-n-slate-12">{{ L.waTitle }}</h2>
          <p class="mt-0.5 text-xs text-n-slate-10">{{ L.waHint }}</p>
        </div>
        <CrmWhatsappWebBinding />
      </div>

      <!-- 收信黑名单（仅管理员/副管理员；规则全公司生效） -->
      <div v-if="canManageBlocklist" v-show="settingsSection === 'blocklist'" class="min-w-0 bg-white py-2">
        <div class="mb-3 min-w-0">
          <h2 class="text-heading-2 text-n-slate-12">{{ L.blTitle }}</h2>
          <p class="mt-0.5 text-xs text-n-slate-10">{{ L.blHint }}</p>
        </div>

        <div class="flex flex-wrap items-center gap-2 mb-3">
          <input
            v-model="blockInput"
            type="text"
            :placeholder="L.blPlaceholder"
            class="w-72 max-w-full h-8 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12"
            @keyup.enter="addBlockRule()"
          />
          <Button
            :label="L.blAdd"
            size="sm"
            color="slate"
            :is-loading="blockBusy"
            @click="addBlockRule()"
          />
        </div>

        <div
          v-if="blockSuggestions.length"
          class="flex flex-wrap items-center gap-2 mb-4"
        >
          <span class="text-xs text-n-slate-10">{{ L.blSuggest }}</span>
          <button
            v-for="item in blockSuggestions"
            :key="item.value"
            type="button"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full reset-base bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
            @click="addBlockRule(item.value)"
          >
            {{ item.value }}
            <span class="text-n-slate-10">({{ item.spam_count }})</span>
          </button>
        </div>

        <p v-if="!blockRules.length" class="text-xs text-n-slate-10">
          {{ L.blEmpty }}
        </p>
        <div v-else class="overflow-hidden rounded-xl border border-[#e6e8ec]">
          <div
            v-for="rule in blockRules"
            :key="rule.id"
            class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3 border-b border-[#eceef1] last:border-b-0"
          >
            <span class="text-sm font-medium truncate shrink-0 text-n-slate-12">
              {{ rule.value }}
            </span>
            <span class="text-xs truncate text-n-slate-10">
              {{ blockHitText(rule) }}
            </span>
            <span
              v-if="rule.created_by_name"
              class="ml-auto text-xs shrink-0 text-n-slate-10"
            >
              {{ rule.created_by_name }} {{ L.blAddedBy }}
            </span>
            <Button
              :label="L.blRemove"
              variant="ghost"
              size="sm"
              :class="rule.created_by_name ? 'shrink-0' : 'ml-auto shrink-0'"
              @click="removeBlockRule(rule)"
            />
          </div>
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
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="handleConfirm"
      @close="markPristine"
      @save="handleConfirm"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
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
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM.MAIL_ACCOUNTS.FORM.PROVIDER') }}
            </label>
            <SelectCard
              block
                v-model="form.provider"
              class="w-full"
              :options="providerOptions"
            />
          </div>
          <div>
            <label class="block mb-0.5 text-heading-3 text-n-slate-12">
              {{ t('CRM.MAIL_ACCOUNTS.FORM.SSL') }}
            </label>
            <SelectCard
              block
                v-model="form.useSsl"
              class="w-full"
              :options="sslOptions"
            />
          </div>
        </div>
        <div
          v-if="form.provider === 'CUSTOM'"
          class="grid grid-cols-1 gap-4 sm:grid-cols-2"
        >
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
        <!-- 收件设置（IMAP / POP3）：认证复用上面的授权码 -->
        <div class="pt-2 mt-1 border-t border-n-weak">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label class="block mb-0.5 text-heading-3 text-n-slate-12">
                收件方式
              </label>
              <SelectCard
                block
                v-model="form.receiveMode"
                class="w-full"
                :options="receiveOptions"
              />
            </div>
            <div v-if="form.receiveMode !== 'off'">
              <label class="block mb-0.5 text-heading-3 text-n-slate-12">
                收件加密
              </label>
              <SelectCard
                block
                v-model="form.imapSsl"
                class="w-full"
                :options="imapSslOptions"
              />
            </div>
          </div>
          <div
            v-if="form.receiveMode !== 'off' && form.provider === 'CUSTOM'"
            class="grid grid-cols-1 gap-4 mt-3 sm:grid-cols-2"
          >
            <Input v-model="form.imapHost" label="收件主机" />
            <Input v-model="form.imapPort" type="number" label="收件端口" />
          </div>
          <p
            v-if="form.receiveMode !== 'off'"
            class="mt-1.5 text-xs text-n-slate-10"
          >
            开启后每 5 分钟自动拉取新邮件到收件箱，认证复用上方的授权码。
          </p>
        </div>
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

    <!-- 签名 新建/编辑 -->
    <Dialog
      ref="sigDialogRef"
      width="2xl"
      overflow-y-auto
      :title="sigEditingId ? L.sigEditTitle : L.sigCreateTitle"
      confirm-button-color="iris"
      :dirty="isSigDirty"
      dirty-save-label="保存"
      @confirm="handleSigConfirm"
      @close="markSigPristine"
      @save="handleSigConfirm"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="sigForm.name"
          :label="L.sigNameLabel"
          :placeholder="L.sigNamePlaceholder"
          autofocus
        />
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.sigBodyLabel }}
          </label>
          <CrmSignatureEditor
            v-model="sigForm.bodyHtml"
            @update:text="sigForm.body = $event"
          />
        </div>
        <label
          class="inline-flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
        >
          <input
            v-model="sigForm.isDefault"
            type="checkbox"
            class="rounded border-n-weak text-n-iris-9 focus:ring-n-iris-9"
          />
          {{ L.sigDefaultLabel }}
        </label>
        <button
          v-if="sigEditingId"
          class="inline-flex items-center self-start gap-1 text-xs text-n-ruby-11 hover:underline"
          @click="removeSignature"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ L.delete }}
        </button>
      </div>
    </Dialog>

    <CrmSignatureGenerator
      :show="showGenerator"
      :prefill="genPrefill"
      @close="showGenerator = false"
      @save="handleGeneratorSave"
    />
  </div>
</template>

<style scoped>
/* 签名卡片预览：约束图片与字号，避免签名里的大图/大字撑破卡片 */
.crm-sig-preview :deep(img) {
  max-width: 100%;
  height: auto;
}
.crm-sig-preview :deep(*) {
  font-size: 11px !important;
  line-height: 1.4 !important;
}
</style>
