<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import FileTile from '@/components/FileTile.vue';
import { fetchDocs } from '@/api/crm';
import { shortDate } from '@/utils/format';

defineOptions({ name: 'DocsPage' });

const router = useRouter();

// filter 留空＝公司文档 + 自己的个人文档（后端 visible_docs 的默认范围）
const VIEWS = [
  { key: 'company', label: '公司资料' },
  { key: 'mine', label: '我的文档' },
  { key: '', label: '全部' },
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
    <PageHeader title="知识库">
      <template #actions>
        <button
          type="button"
          aria-label="上传文档"
          class="wt-fab-round wt-press"
          @click="router.push({ name: 'more' })"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-none px-4 pb-2">
      <div class="wt-search">
        <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-search" />
        <input
          v-model="keyword"
          type="search"
          enterkeyhint="search"
          placeholder="搜标题 / 摘要 / 文件名"
          class="flex-1 min-w-0 text-[15px] bg-transparent outline-none text-[color:var(--pb-ink)] placeholder:text-[color:var(--pb-ink-3)]"
          @search="load()"
          @keyup.enter="load()"
        />
      </div>

      <!-- 分段：三项，第 2/3 项之间一条细竖线（参考稿就是这样分的） -->
      <div class="flex items-center gap-1 p-1 mt-2.5 rounded-full pb-well">
        <template v-for="(v, k) in VIEWS" :key="v.key">
          <span
            v-if="k === 2"
            class="self-stretch w-px my-2 bg-[color:var(--pb-sep)]"
          />
          <button
            type="button"
            class="flex-1 rounded-full h-10 text-[14px] transition-colors"
            :class="
              view === v.key
                ? 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)] font-semibold'
                : 'text-[color:var(--pb-ink-2)] font-medium'
            "
            @click="switchView(v.key)"
          >
            {{ v.label }}
          </button>
        </template>
      </div>

          </div>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="这里还没有文档"
        @retry="load()"
      >
        <!-- 三列网格：一条文档挂多个附件时当「文件夹」，挂一个时按扩展名出类型图标。
             副行对应显示「N 项」或文件日期（按定稿：不显示由谁添加）。 -->
        <ul class="grid grid-cols-3 pt-3 gap-x-2 gap-y-8">
          <li v-for="d in list" :key="d.id">
            <button
              type="button"
              class="flex flex-col items-center w-full gap-1.5 text-center wt-press"
              @click="router.push({ name: 'doc-detail', params: { id: d.id } })"
            >
              <FileTile
                class="size-[88px]"
                :filename="(d.files?.length || 0) > 1 ? '' : d.files?.[0]?.filename || d.name"
                :count="d.id"
              />
              <span
                class="w-full text-[15px] font-semibold leading-[20px] line-clamp-2 text-[color:var(--pb-ink)]"
              >
                {{ d.name }}
              </span>
              <span class="text-[13px] leading-[18px] text-[color:var(--pb-ink-3)]">
                {{ (d.files?.length || 0) > 1 ? `${d.files.length} 项` : shortDate(d.updated_at) }}
              </span>
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
