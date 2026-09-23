<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchEmails, fetchEmailCounts, fetchEmailsFetchNow } from '@/api/crm';
import { shortDateTime, counterpartyOf, snippet } from '@/utils/format';

defineOptions({ name: 'MailPage' });

const PER_PAGE = 25;

// 视图 = 后端 folder / filter 两个参数的组合，移动端只保留最常用的四个
const VIEWS = [
  { key: 'INBOX', label: '收件箱', params: { folder: 'INBOX' }, badge: 'unread' },
  { key: 'unread', label: '未读', params: { filter: 'unread' }, badge: 'unread' },
  { key: 'starred', label: '星标', params: { filter: 'starred' }, badge: 'starred' },
  { key: 'SENT', label: '已发送', params: { folder: 'SENT' } },
  { key: 'DRAFT', label: '草稿', params: { folder: 'DRAFT' }, badge: 'DRAFT' },
];

const router = useRouter();
const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('INBOX');
const keyword = ref('');
const counts = ref({});
const loading = ref(true);
const loadingMore = ref(false);
const fetching = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => list.value.length < total.value);
const activeView = computed(() => VIEWS.find(v => v.key === view.value));
const badgeOf = v => (v.badge ? counts.value[v.badge] || 0 : 0);

const load = async ({ append = false } = {}) => {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchEmails({
      per_page: PER_PAGE,
      page: page.value,
      ...activeView.value.params,
      q: keyword.value || undefined,
    });
    const rows = r.data?.payload || [];
    list.value = append ? [...list.value, ...rows] : rows;
    total.value = r.data?.meta?.count ?? rows.length;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    if (!append) failed.value = true;
  } finally {
    loading.value = false;
    loadingMore.value = false;
  }
};

const loadCounts = async () => {
  try {
    const r = await fetchEmailCounts();
    counts.value = r.data || {};
  } catch {
    // 角标失败不影响列表
  }
};

const loadMore = () => {
  page.value += 1;
  load({ append: true });
};

const switchView = key => {
  if (view.value === key) return;
  view.value = key;
  load();
};

// 手动收信：后端异步排任务，等几秒再刷新列表
const fetchNow = async () => {
  fetching.value = true;
  try {
    await fetchEmailsFetchNow();
    await new Promise(r => setTimeout(r, 4000));
    await Promise.all([load(), loadCounts()]);
  } finally {
    fetching.value = false;
  }
};

const open = id => router.push({ name: 'mail-detail', params: { id } });

const refresh = () => Promise.all([load(), loadCounts()]);

onMounted(refresh);
onActivated(() => {
  if (!loading.value) refresh();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="邮件" :subtitle="total ? `共 ${total} 封` : ''">
      <template #actions>
        <button
          type="button"
          aria-label="收信"
          class="grid rounded-full size-9 place-items-center text-[color:var(--pb-ink-2)] active:bg-[color:var(--pb-fill)] disabled:opacity-40"
          :disabled="fetching"
          @click="fetchNow"
        >
          <span
            class="size-5 i-lucide-refresh-cw"
            :class="fetching ? 'animate-spin' : ''"
          />
        </button>
        <button
          type="button"
          aria-label="写邮件"
          class="grid rounded-full size-9 place-items-center text-[color:var(--pb-accent)] active:bg-[color:var(--pb-fill)]"
          @click="router.push({ name: 'mail-compose' })"
        >
          <span class="size-5 i-lucide-square-pen" />
        </button>
      </template>

      <template #below>
        <div class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-[color:var(--pb-ink-3)] i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              enterkeyhint="search"
              placeholder="搜主题 / 收发件人 / 正文"
              class="pl-9 wt-field"
              @search="load()"
              @keyup.enter="load()"
            />
          </div>
        </div>
        <div class="flex items-center gap-2 px-4 pb-3 overflow-x-auto [&::-webkit-scrollbar]:hidden">
          <button
            v-for="v in VIEWS"
            :key="v.key"
            type="button"
            class="flex items-center flex-none h-8 gap-1.5 px-3 text-sm leading-none rounded-full"
            :class="
              view === v.key
                ? 'wt-pill-on'
                : 'wt-pill-off'
            "
            @click="switchView(v.key)"
          >
            {{ v.label }}
            <span
              v-if="badgeOf(v)"
              class="px-1.5 text-[11px] rounded-full"
              :class="view === v.key ? 'bg-white/25' : 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'"
            >
              {{ badgeOf(v) }}
            </span>
          </button>
        </div>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="这个文件夹里没有邮件"
        @retry="load()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="m in list" :key="m.id">
            <button
              type="button"
              class="flex w-full gap-2.5 px-3.5 py-3 text-left wt-glass wt-press"
              @click="open(m.id)"
            >
              <!-- 圆点常驻占位：只切换颜色不切换存在，否则同一列文字会在已读/未读间左右跳。
                   未读用品牌黄，已读用中性灰点。 -->
              <span
                class="flex-none mt-1.5 rounded-full size-2"
                :class="
                  !m.is_read && m.folder === 'INBOX'
                    ? 'brand-fill'
                    : 'bg-[color:var(--pb-ink-3)]/40'
                "
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span
                    class="flex-1 min-w-0 truncate text-[13px]"
                    :class="
                      !m.is_read && m.folder === 'INBOX'
                        ? 'font-semibold text-[color:var(--pb-ink)]'
                        : 'text-[color:var(--pb-ink-2)]'
                    "
                  >
                    {{ m.customer_name || counterpartyOf(m) }}
                  </span>
                  <span
                    v-if="m.is_starred"
                    class="flex-none size-3.5 text-[color:var(--pb-brand-ink)] i-ri-star-fill"
                  />
                  <span
                    v-if="m.files?.length"
                    class="flex-none size-3.5 text-[color:var(--pb-ink-3)] i-lucide-paperclip"
                  />
                  <span class="flex-none text-[12px] tabular-nums text-[color:var(--pb-ink-3)]">
                    {{ shortDateTime(m.email_date) }}
                  </span>
                </div>

                <div
                  class="mt-0.5 truncate text-[15px] leading-5"
                  :class="
                    !m.is_read && m.folder === 'INBOX'
                      ? 'font-semibold text-[color:var(--pb-ink)]'
                      : 'text-[color:var(--pb-ink)]'
                  "
                >
                  {{ m.subject || '（无主题）' }}
                </div>

                <!-- 摘要行：光看主题常常判断不出要不要点进去 -->
                <div
                  v-if="snippet(m.body)"
                  class="mt-0.5 truncate text-[13px] leading-[18px] text-[color:var(--pb-ink-3)]"
                >
                  {{ snippet(m.body) }}
                </div>

                <div v-if="m.send_status === 'FAILED'" class="mt-1 text-[12px] text-[#C4383C]">
                  发送失败
                </div>
              </div>
            </button>
          </li>
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="w-full mt-3 wt-btn-ghost"
          :disabled="loadingMore"
          @click="loadMore"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-36" />
      </DataState>
    </div>
  </div>
</template>
