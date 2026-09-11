<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchDocs } from '@/api/crm';
import { shortDate } from '@/utils/format';

defineOptions({ name: 'DocsPage' });

const router = useRouter();

const VIEWS = [
  { key: 'company', label: '公司资料' },
  { key: 'mine', label: '我的文档' },
];

const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('company');
const keyword = ref('');
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => list.value.length < total.value);

const load = async ({ append = false } = {}) => {
  if (append) loadingMore.value = true;
  else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchDocs({
      page: page.value,
      filter: view.value,
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

const switchView = key => {
  if (view.value === key) return;
  view.value = key;
  load();
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="知识库" :subtitle="total ? `共 ${total} 篇` : ''">
      <template #below>
        <div class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-n-slate-10 i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              enterkeyhint="search"
              placeholder="搜标题 / 摘要"
              class="pl-9 wt-field"
              @search="load()"
              @keyup.enter="load()"
            />
          </div>
        </div>
        <div class="flex items-center gap-2 px-4 pb-3">
          <button
            v-for="v in VIEWS"
            :key="v.key"
            type="button"
            class="h-8 px-3 text-sm leading-none rounded-full"
            :class="
              view === v.key
                ? 'bg-n-iris-9 text-white font-medium'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
            @click="switchView(v.key)"
          >
            {{ v.label }}
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
        empty-text="这里还没有文档"
        @retry="load()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="d in list" :key="d.id">
            <button
              type="button"
              class="w-full p-3 text-left wt-card active:bg-n-alpha-1"
              @click="router.push({ name: 'doc-detail', params: { id: d.id } })"
            >
              <div class="flex items-start gap-3">
                <span class="flex-none mt-0.5 size-4 text-n-slate-10 i-lucide-file-text" />
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-n-slate-12">{{ d.name }}</div>
                  <div v-if="d.summary" class="mt-0.5 text-xs truncate text-n-slate-11">
                    {{ d.summary }}
                  </div>
                  <div class="mt-1 text-xs text-n-slate-10">
                    {{ d.category || '未分类' }}
                    <template v-if="d.files?.length"> · {{ d.files.length }} 个附件</template>
                    · {{ shortDate(d.updated_at) }}
                  </div>
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
          @click="page += 1; load({ append: true })"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
