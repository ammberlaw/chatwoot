<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import DOMPurify from 'dompurify';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import {
  fetchEmail,
  updateEmail,
  deleteEmail,
  aiTranslate,
  aiSummarize,
} from '@/api/crm';
import { shortDateTime } from '@/utils/format';

defineOptions({ name: 'MailDetailPage' });

const route = useRoute();
const router = useRouter();

const email = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);
const showRaw = ref(false);

// 正文来自外部邮件，必须净化后再 v-html；顺带去掉固定宽度，免得在手机上横向撑出去
const safeHtml = computed(() => {
  const html = email.value?.body_html;
  if (!html) return '';
  return DOMPurify.sanitize(html, { FORBID_TAGS: ['style'], FORBID_ATTR: ['width'] });
});

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchEmail(route.params.id);
    email.value = r.data || null;
    staleAt.value = r.fromCache ? r.at : null;
    // 打开即已读（缓存兜底时不写回）
    if (email.value && !r.fromCache && !email.value.is_read) {
      await updateEmail(email.value.id, { is_read: true });
      email.value.is_read = true;
    }
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const toggleStar = async () => {
  const next = !email.value.is_starred;
  email.value.is_starred = next;
  try {
    await updateEmail(email.value.id, { is_starred: next });
  } catch {
    email.value.is_starred = !next;
  }
};

const reply = () =>
  router.push({ name: 'mail-compose', query: { reply: route.params.id } });

// ── 更多操作：标记未读 / 删除 / AI ──
const moreOpen = ref(false);
const busy = ref(false);
const actionError = ref('');

const markUnread = async () => {
  busy.value = true;
  try {
    await updateEmail(email.value.id, { is_read: false });
    moreOpen.value = false;
    router.back();
  } catch {
    actionError.value = '操作失败，请重试';
  } finally {
    busy.value = false;
  }
};

const remove = async () => {
  busy.value = true;
  try {
    await deleteEmail(email.value.id);
    moreOpen.value = false;
    router.back();
  } catch {
    actionError.value = '删除失败，请重试';
  } finally {
    busy.value = false;
  }
};

// AI 结果单开一个弹层展示，不动原邮件内容
const aiOpen = ref(false);
const aiTitle = ref('');
const aiText = ref('');
const aiLoading = ref(false);

const runAi = async (title, fn) => {
  aiTitle.value = title;
  aiText.value = '';
  aiOpen.value = true;
  moreOpen.value = false;
  aiLoading.value = true;
  try {
    const { data } = await fn();
    aiText.value = data.summary || [data.subject, data.body].filter(Boolean).join('\n\n');
  } catch (e) {
    // 后端 15s 超时会走这里，如实告诉用户别干等
    aiText.value =
      e.response?.data?.message ||
      (e.response ? `AI 处理失败（HTTP ${e.response.status}）` : 'AI 请求超时或网络不可用');
  } finally {
    aiLoading.value = false;
  }
};

const translate = () => runAi('翻译成中文', () => aiTranslate(route.params.id));
const summarize = () => {
  const addr = (email.value.folder === 'SENT' ? email.value.to_address : email.value.from_address) || '';
  const clean = (addr.match(/<(.+?)>/)?.[1] || addr.split(',')[0] || '').trim();
  return runAi('往来摘要', () => aiSummarize(clean));
};

const kb = size =>
  size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`;

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="email?.subject || '邮件'">
      <template #actions>
        <button
          v-if="email"
          type="button"
          aria-label="更多操作"
          class="grid rounded-full size-9 place-items-center text-n-slate-11 active:bg-n-alpha-1"
          @click="moreOpen = true"
        >
          <span class="size-5 i-lucide-ellipsis" />
        </button>
        <button
          v-if="email"
          type="button"
          aria-label="星标"
          class="grid rounded-full size-9 place-items-center active:bg-n-alpha-1"
          :class="email.is_starred ? 'text-n-amber-11' : 'text-n-slate-10'"
          @click="toggleStar"
        >
          <span class="size-5 i-lucide-star" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!email"
        :stale-at="staleAt"
        empty-text="邮件不存在或无权查看"
        @retry="load"
      >
        <h1 class="text-base font-semibold leading-snug text-n-slate-12">
          {{ email.subject || '（无主题）' }}
        </h1>

        <div class="p-3 mt-3 text-xs wt-card text-n-slate-11">
          <div class="flex gap-2">
            <span class="flex-none w-10 text-n-slate-10">发件</span>
            <span class="flex-1 break-all">{{ email.from_address }}</span>
          </div>
          <div class="flex gap-2 mt-1.5">
            <span class="flex-none w-10 text-n-slate-10">收件</span>
            <span class="flex-1 break-all">{{ email.to_address }}</span>
          </div>
          <div v-if="email.cc_address" class="flex gap-2 mt-1.5">
            <span class="flex-none w-10 text-n-slate-10">抄送</span>
            <span class="flex-1 break-all">{{ email.cc_address }}</span>
          </div>
          <div class="flex gap-2 mt-1.5">
            <span class="flex-none w-10 text-n-slate-10">时间</span>
            <span class="flex-1">{{ shortDateTime(email.email_date) }}</span>
          </div>
          <button
            v-if="email.crm_customer_id"
            type="button"
            class="flex gap-2 mt-1.5 w-full text-left"
            @click="
              router.push({
                name: 'customer-detail',
                params: { id: email.crm_customer_id },
              })
            "
          >
            <span class="flex-none w-10 text-n-slate-10">客户</span>
            <span class="flex-1 underline text-n-iris-11 underline-offset-2">
              {{ email.customer_name }}
            </span>
          </button>
        </div>

        <!-- 附件：点开走系统浏览器下载，不在 webview 里内嵌预览 -->
        <ul v-if="email.files?.length" class="flex flex-col gap-2 mt-3">
          <li v-for="f in email.files" :key="f.id">
            <a
              :href="f.url"
              target="_blank"
              rel="noopener"
              class="flex items-center gap-3 p-3 wt-card active:bg-n-alpha-1"
            >
              <span class="flex-none size-4 text-n-slate-10 i-lucide-paperclip" />
              <span class="flex-1 text-sm truncate text-n-iris-11">{{ f.filename }}</span>
              <span class="flex-none text-xs text-n-slate-10">{{ kb(f.byte_size) }}</span>
            </a>
          </li>
        </ul>

        <!-- 正文：HTML 邮件自带排版与底色，不再套一层卡片，免得双层边框 -->
        <!-- eslint-disable-next-line vue/no-v-html -->
        <div
          v-if="safeHtml && !showRaw"
          class="mt-3 overflow-hidden text-sm leading-relaxed break-words rounded-2xl wt-mail-body text-n-slate-12"
          v-html="safeHtml"
        />
        <div v-else class="p-3 mt-3 wt-card">
          <p class="text-sm leading-relaxed break-words whitespace-pre-line text-n-slate-12">
            {{ email.body || '（空白邮件）' }}
          </p>
        </div>

        <button
          v-if="safeHtml"
          type="button"
          class="mt-2 text-xs text-n-slate-10"
          @click="showRaw = !showRaw"
        >
          {{ showRaw ? '切回原排版' : '切纯文本' }}
        </button>

        <div class="h-6" />
      </DataState>
    </div>

    <AppSheet :open="moreOpen" title="更多操作" @close="moreOpen = false">
      <div class="flex flex-col gap-2">
        <button type="button" class="w-full wt-btn-ghost" :disabled="busy" @click="translate">
          <span class="mr-1.5 size-4 i-lucide-languages" />
          翻译成中文
        </button>
        <button type="button" class="w-full wt-btn-ghost" :disabled="busy" @click="summarize">
          <span class="mr-1.5 size-4 i-lucide-sparkles" />
          与对方的往来摘要
        </button>
        <button
          v-if="email?.folder === 'INBOX'"
          type="button"
          class="w-full wt-btn-ghost"
          :disabled="busy"
          @click="markUnread"
        >
          <span class="mr-1.5 size-4 i-lucide-mail" />
          标记为未读
        </button>
        <button
          type="button"
          class="w-full wt-btn text-n-ruby-11 bg-n-ruby-3 active:bg-n-ruby-4"
          :disabled="busy"
          @click="remove"
        >
          删除邮件
        </button>
        <p v-if="actionError" class="text-sm text-n-ruby-11">{{ actionError }}</p>
      </div>
    </AppSheet>

    <AppSheet :open="aiOpen" :title="aiTitle" @close="aiOpen = false">
      <p v-if="aiLoading" class="py-6 text-sm text-center text-n-slate-11">AI 处理中…</p>
      <p v-else class="text-sm leading-relaxed whitespace-pre-line text-n-slate-12">
        {{ aiText }}
      </p>
    </AppSheet>

    <div
      v-if="email"
      class="flex-none px-4 pt-2 pb-2 border-t border-n-weak bg-n-background pb-safeBottom"
    >
      <button type="button" class="w-full wt-btn-primary" @click="reply">
        <span class="mr-1.5 size-4 i-lucide-reply" />
        回复
      </button>
    </div>
  </div>
</template>
