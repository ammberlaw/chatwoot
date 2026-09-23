<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import DOMPurify from 'dompurify';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchDoc } from '@/api/crm';
import { shortDate } from '@/utils/format';

defineOptions({ name: 'DocDetailPage' });

const route = useRoute();
const doc = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

// 正文是富文本编辑器存的 HTML，渲染前净化
const safeBody = computed(() =>
  doc.value?.body ? DOMPurify.sanitize(doc.value.body, { FORBID_TAGS: ['style'] }) : ''
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchDoc(route.params.id);
    doc.value = r.data?.payload || r.data || null;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const kb = size =>
  size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`;

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="doc?.name || '文档'" />

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!doc"
        :stale-at="staleAt"
        empty-text="文档不存在或无权查看"
        @retry="load"
      >
        <h1 class="text-base font-semibold leading-snug text-[color:var(--pb-ink)]">{{ doc.name }}</h1>
        <p class="mt-1 text-xs text-[color:var(--pb-ink-3)]">
          {{ doc.category || '未分类' }} · 更新于 {{ shortDate(doc.updated_at) }}
        </p>

        <p v-if="doc.summary" class="p-3 mt-3 text-sm leading-relaxed wt-card text-[color:var(--pb-ink-2)]">
          {{ doc.summary }}
        </p>

        <ul v-if="doc.files?.length" class="flex flex-col gap-2 mt-3">
          <li v-for="f in doc.files" :key="f.id">
            <a
              :href="f.url"
              target="_blank"
              rel="noopener"
              class="flex items-center gap-3 p-3 wt-card active:bg-[color:var(--pb-fill)]"
            >
              <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-paperclip" />
              <span class="flex-1 text-sm truncate text-[color:var(--pb-accent)]">{{ f.filename }}</span>
              <span class="flex-none text-xs text-[color:var(--pb-ink-3)]">{{ kb(f.byte_size) }}</span>
            </a>
          </li>
        </ul>

        <!-- eslint-disable-next-line vue/no-v-html -->
        <div
          v-if="safeBody"
          class="p-3 mt-3 text-sm leading-relaxed break-words wt-card wt-mail-body text-[color:var(--pb-ink)]"
          v-html="safeBody"
        />

        <div class="h-6" />
      </DataState>
    </div>
  </div>
</template>
