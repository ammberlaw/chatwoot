<script setup>
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import FormField from '@/components/FormField.vue';
import AttachmentField from '@/components/AttachmentField.vue';
import AppSheet from '@/components/AppSheet.vue';
import {
  fetchEmail,
  fetchMailAccounts,
  sendEmail,
  sendEmailWithFiles,
  fetchEmailTemplates,
  aiCompose,
} from '@/api/crm';
import { shortDateTime } from '@/utils/format';

defineOptions({ name: 'MailComposePage' });

const route = useRoute();
const router = useRouter();

const accounts = ref([]);
const form = ref({
  from_address: '',
  to_address: '',
  cc_address: '',
  subject: '',
  body: '',
  crm_customer_id: null,
  contact_id: null,
});
const showCc = ref(false);
const files = ref([]);
const loading = ref(true);
const sending = ref(false);
const error = ref('');

// ── 邮件模板 ──
const tplOpen = ref(false);
const templates = ref([]);
const tplLoading = ref(false);

const openTemplates = async () => {
  tplOpen.value = true;
  if (templates.value.length) return;
  tplLoading.value = true;
  try {
    const r = await fetchEmailTemplates();
    templates.value = r.data?.payload || [];
  } catch {
    templates.value = [];
  } finally {
    tplLoading.value = false;
  }
};

// 套用模板只填空白处，不覆盖已经写了的内容
const applyTemplate = t => {
  if (t.subject_template && !form.value.subject) form.value.subject = t.subject_template;
  if (t.body) {
    // 模板正文是 HTML，移动端正文按纯文本发，剥标签后再塞
    const text = t.body.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();
    form.value.body = form.value.body ? `${text}\n\n${form.value.body}` : text;
  }
  tplOpen.value = false;
};

// ── AI 写信 ──
const aiOpen = ref(false);
const aiIntent = ref('');
const aiLoading = ref(false);
const aiError = ref('');

const runCompose = async () => {
  if (!aiIntent.value.trim()) {
    aiError.value = '先说一句这封邮件要写什么';
    return;
  }
  aiLoading.value = true;
  aiError.value = '';
  try {
    const { data } = await aiCompose(aiIntent.value.trim(), form.value.body || undefined);
    if (data.subject) form.value.subject = data.subject;
    if (data.body) form.value.body = data.body;
    aiOpen.value = false;
  } catch (e) {
    aiError.value =
      e.response?.data?.message ||
      (e.response ? `AI 生成失败（HTTP ${e.response.status}）` : 'AI 请求超时或网络不可用');
  } finally {
    aiLoading.value = false;
  }
};

// 回复：带上原文引用，收件人取原发件人，主题补 Re:
const buildQuote = src =>
  `\n\n---------- 原邮件 ----------\n发件人：${src.from_address}\n时间：${shortDateTime(
    src.email_date
  )}\n主题：${src.subject || '（无主题）'}\n\n${src.body || ''}`;

const load = async () => {
  try {
    const { data } = await fetchMailAccounts();
    accounts.value = (data?.payload || []).filter(a => a.is_active);
    const preferred = accounts.value.find(a => a.is_default) || accounts.value[0];
    form.value.from_address = preferred?.email_address || '';

    if (route.query.reply) {
      const r = await fetchEmail(route.query.reply);
      const src = r.data || {};
      form.value.to_address = src.from_address || '';
      form.value.subject = /^re:/i.test(src.subject || '')
        ? src.subject
        : `Re: ${src.subject || ''}`;
      form.value.body = buildQuote(src);
      form.value.crm_customer_id = src.crm_customer_id || null;
      form.value.contact_id = src.contact_id || null;
      // 回复时发件邮箱沿用原邮件收到的那个（别用默认邮箱回，收件人会看到换了地址）
      const own = accounts.value.find(a =>
        (src.to_address || '').toLowerCase().includes(a.email_address.toLowerCase())
      );
      if (own) form.value.from_address = own.email_address;
    }
  } catch {
    error.value = '加载邮箱账户失败，请检查网络后重试';
  } finally {
    loading.value = false;
  }
};

const send = async () => {
  if (!form.value.from_address) {
    error.value = '请先在网页端「邮箱账户」里配置发信邮箱';
    return;
  }
  if (!form.value.to_address.trim()) {
    error.value = '请填写收件人';
    return;
  }
  sending.value = true;
  error.value = '';
  try {
    const payload = {
      ...form.value,
      cc_address: form.value.cc_address || null,
      folder: 'SENT',
      email_date: new Date().toISOString(),
      // 正文按纯文本发；send_now 触发后端排 SMTP 发送任务
      body_html: null,
      send_now: true,
    };
    if (files.value.length) {
      await sendEmailWithFiles(payload, files.value);
    } else {
      await sendEmail(payload);
    }
    router.back();
  } catch (e) {
    // 撞单拦截（收件人是同事的客户）走 422 + error 文案，要原样透给用户
    error.value =
      e.response?.data?.error ||
      e.response?.data?.message ||
      (e.response ? `发送失败（HTTP ${e.response.status}）` : '网络不可用，发送失败');
  } finally {
    sending.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="route.query.reply ? '回复邮件' : '写邮件'">
      <template #actions>
        <button
          type="button"
          aria-label="用模板"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="openTemplates"
        >
          <span class="size-5 i-lucide-file-text" />
        </button>
        <button
          type="button"
          aria-label="AI 写信"
          class="grid rounded-full size-9 place-items-center text-n-iris-11 active:bg-n-alpha-1"
          @click="aiOpen = true"
        >
          <span class="size-5 i-lucide-sparkles" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-4 overflow-y-auto">
      <p v-if="loading" class="py-10 text-sm text-center text-n-slate-11">加载中…</p>

      <div v-else class="flex flex-col gap-4">
        <FormField v-if="accounts.length > 1" label="发件邮箱">
          <select v-model="form.from_address" class="wt-field">
            <option v-for="a in accounts" :key="a.id" :value="a.email_address">
              {{ a.email_address }}
            </option>
          </select>
        </FormField>
        <FormField v-else label="发件邮箱">
          <input :value="form.from_address || '未配置'" type="text" disabled class="wt-field" />
        </FormField>

        <FormField label="收件人" required hint="多个收件人用英文逗号分隔">
          <input
            v-model="form.to_address"
            type="email"
            inputmode="email"
            autocapitalize="off"
            autocorrect="off"
            class="wt-field"
          />
        </FormField>

        <button
          v-if="!showCc"
          type="button"
          class="self-start text-xs text-n-iris-11"
          @click="showCc = true"
        >
          + 添加抄送
        </button>
        <FormField v-else label="抄送">
          <input
            v-model="form.cc_address"
            type="email"
            inputmode="email"
            autocapitalize="off"
            autocorrect="off"
            class="wt-field"
          />
        </FormField>

        <FormField label="主题">
          <input v-model="form.subject" type="text" class="wt-field" />
        </FormField>

        <FormField label="正文">
          <textarea v-model="form.body" rows="10" class="wt-field" />
        </FormField>

        <AttachmentField v-model="files" />

        <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
        <div class="h-2" />
      </div>
    </div>

    <AppSheet :open="tplOpen" title="选择模板" @close="tplOpen = false">
      <p v-if="tplLoading" class="py-6 text-sm text-center text-n-slate-11">加载中…</p>
      <p v-else-if="!templates.length" class="py-6 text-sm text-center text-n-slate-11">
        还没有可用模板
      </p>
      <ul v-else class="overflow-hidden wt-card">
        <li v-for="t in templates" :key="t.id">
          <button
            type="button"
            class="w-full px-3 py-3 text-left border-b last:border-b-0 border-n-weak active:bg-n-alpha-1"
            @click="applyTemplate(t)"
          >
            <div class="text-sm font-medium truncate text-n-slate-12">{{ t.name }}</div>
            <div v-if="t.subject_template" class="mt-0.5 text-xs truncate text-n-slate-10">
              {{ t.subject_template }}
            </div>
          </button>
        </li>
      </ul>
    </AppSheet>

    <AppSheet :open="aiOpen" title="AI 写信" @close="aiOpen = false">
      <FormField label="这封邮件要写什么" required hint="例如：催客户确认 PI，语气客气但要给个期限">
        <textarea v-model="aiIntent" rows="4" class="wt-field" />
      </FormField>
      <p v-if="aiError" class="mt-3 text-sm text-n-ruby-11">{{ aiError }}</p>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn-primary"
          :disabled="aiLoading"
          @click="runCompose"
        >
          {{ aiLoading ? '生成中…' : '生成' }}
        </button>
      </template>
    </AppSheet>

    <div class="flex-none px-4 pt-2 pb-2 border-t border-n-weak bg-n-background pb-safeBottom">
      <button
        type="button"
        class="w-full wt-btn-primary"
        :disabled="sending || loading"
        @click="send"
      >
        {{ sending ? '发送中…' : '发送' }}
      </button>
    </div>
  </div>
</template>
