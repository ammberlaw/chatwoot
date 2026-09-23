<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchPriceList } from '@/api/crm';
import { API_BASE } from '@/api/client';
import { shortDate } from '@/utils/format';

defineOptions({ name: 'PriceListDetailPage' });

const route = useRoute();

const list = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);
const keyword = ref('');

const columns = computed(() => list.value?.columns || []);

// 核价表是宽表，手机上摊不开：每行渲染成一张卡，列名做左侧标签。
// 第一列当卡片标题（一般是名称或型号）。
const rows = computed(() => {
  const items = list.value?.items || [];
  const q = keyword.value.trim().toLowerCase();
  const mapped = items.map(it => {
    // values 是与 columns 按下标对齐的数组，不是以列名为键的对象
    const values = columns.value.map((c, i) => ({
      label: c.label,
      value: it.values?.[i] ?? '',
      isPrice: c.type === 'price',
    }));
    return {
      id: it.id,
      title: values.find(v => v.value)?.value || '—',
      rest: values.slice(1).filter(v => v.value !== '' && v.value !== null),
      remark: it.remark,
      image: it.image_url ? `${API_BASE}${it.image_url}` : null,
    };
  });
  if (!q) return mapped;
  return mapped.filter(r =>
    [r.title, r.remark, ...r.rest.map(v => v.value)].join(' ').toLowerCase().includes(q)
  );
});

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchPriceList(route.params.id);
    list.value = r.data || null;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader
      back
      :title="list?.title || '核价表'"
      :subtitle="
        list
          ? [list.product_line, list.status_label, list.effective_on && `${shortDate(list.effective_on)} 生效`]
              .filter(Boolean)
              .join(' · ')
          : ''
      "
    >
      <template v-if="list?.items?.length" #below>
        <div class="px-4 pb-3">
          <div class="relative">
            <span
              class="absolute -translate-y-1/2 pointer-events-none left-3 top-1/2 size-4 text-[color:var(--pb-ink-3)] i-lucide-search"
            />
            <input
              v-model="keyword"
              type="search"
              placeholder="在本表内搜型号 / 参数"
              class="pl-9 wt-field"
            />
          </div>
        </div>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list"
        :stale-at="staleAt"
        empty-text="核价表不存在或无权查看"
        @retry="load"
      >
        <div v-if="list.header_note" class="p-3 text-xs leading-relaxed whitespace-pre-line wt-card text-[color:var(--pb-ink-2)]">
          {{ list.header_note }}
        </div>

        <p v-if="!rows.length" class="py-10 text-sm text-center text-[color:var(--pb-ink-2)]">
          没有匹配的行
        </p>
        <ul v-else class="flex flex-col gap-2 mt-3">
          <li v-for="r in rows" :key="r.id" class="p-3 wt-card">
            <div class="flex items-start gap-3">
              <img
                v-if="r.image"
                :src="r.image"
                alt=""
                class="flex-none object-cover rounded-lg size-14 bg-[color:var(--pb-fill)]"
              />
              <div class="flex-1 min-w-0">
                <div class="text-sm font-semibold break-words text-[color:var(--pb-ink)]">{{ r.title }}</div>
                <dl class="mt-1.5 flex flex-col gap-1">
                  <div v-for="v in r.rest" :key="v.label" class="flex items-start gap-2">
                    <dt class="flex-none text-xs w-24 text-[color:var(--pb-ink-3)]">{{ v.label }}</dt>
                    <dd
                      class="flex-1 text-xs break-words"
                      :class="v.isPrice ? 'font-medium text-[color:var(--pb-ink)]' : 'text-[color:var(--pb-ink-2)]'"
                    >
                      {{ v.value }}
                    </dd>
                  </div>
                </dl>
                <p v-if="r.remark" class="mt-1.5 text-xs text-[color:var(--pb-ink-3)]">{{ r.remark }}</p>
              </div>
            </div>
          </li>
        </ul>

        <div
          v-if="list.rules_note"
          class="p-3 mt-3 text-xs leading-relaxed whitespace-pre-line wt-card text-[color:var(--pb-ink-2)]"
        >
          {{ list.rules_note }}
        </div>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
