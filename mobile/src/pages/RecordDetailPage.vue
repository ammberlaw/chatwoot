<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchRecord } from '@/api/crm';
import { RECORDS } from '@/constants/records';
import { money } from '@/utils/format';

defineOptions({ name: 'RecordDetailPage' });

const route = useRoute();
const router = useRouter();

const kind = computed(() => route.meta.kind);
const cfg = computed(() => RECORDS[kind.value]);

const record = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

const rows = computed(() =>
  record.value ? cfg.value.detail(record.value).filter(r => r.value) : []
);
const items = computed(() =>
  cfg.value.itemsKey ? record.value?.[cfg.value.itemsKey] || [] : []
);
const files = computed(() =>
  cfg.value.filesKey ? record.value?.[cfg.value.filesKey] || [] : []
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchRecord(kind.value, route.params.id);
    // 有的 show 包一层 payload，有的直接是对象
    record.value = r.data?.payload || r.data || null;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

// 各类单据的明细行字段名不完全一致，取第一个有值的
const pick = (item, keys) => keys.map(k => item[k]).find(v => v !== undefined && v !== null && v !== '');

const itemName = it => pick(it, ['name', 'product_name', 'description', 'title']) || '—';
const itemQty = it => pick(it, ['qty', 'quantity']) ?? '';
const itemUnit = it => pick(it, ['unit']) || '';
const itemAmount = it => {
  const micros = pick(it, ['amount_micros', 'total_micros', 'subtotal_micros']);
  return micros ? money(micros, record.value?.currency || record.value?.order_currency || record.value?.quote_currency) : '';
};

const kb = size =>
  size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`;

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="cfg.title" />

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!record"
        :stale-at="staleAt"
        :empty-text="`${cfg.title}不存在或无权查看`"
        @retry="load"
      >
        <div class="flex items-start gap-3">
          <div class="flex-1 min-w-0">
            <h1
              class="text-[20px] font-bold leading-7 tracking-[-0.4px] text-[color:var(--pb-ink)]"
            >
              {{ cfg.row(record).title }}
            </h1>
            <p
              v-if="record.customer_name"
              class="mt-0.5 text-[14px] leading-5 text-[color:var(--pb-ink-3)]"
            >
              {{ record.customer_name }}
            </p>
          </div>
          <span
            v-if="cfg.statusLabels[record[cfg.statusKey]]"
            class="flex-none px-2.5 rounded-full text-[12px] leading-6"
            :class="cfg.statusTone[record[cfg.statusKey]] || 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'"
          >
            {{ cfg.statusLabels[record[cfg.statusKey]] }}
          </span>
        </div>

        <div v-if="rows.length" class="mt-3 overflow-hidden wt-glass">
          <div
            v-for="(row, i) in rows"
            :key="row.label"
            class="flex items-start gap-3 px-4 py-3"
            :class="i ? 'border-t-[0.5px] border-[color:var(--pb-sep)]' : ''"
          >
            <span class="flex-none w-[72px] text-[14px] leading-5 text-[color:var(--pb-ink-3)]">
              {{ row.label }}
            </span>
            <span
              class="flex-1 text-[15px] leading-5 text-right break-words whitespace-pre-line text-[color:var(--pb-ink)]"
            >
              {{ row.value }}
            </span>
          </div>
        </div>

        <!-- 相关信息：从单据跳到客户档案 / 跟进 / 文件。
             这几样单据详情本身都拿不到，跳过去看才是对的。 -->
        <template v-if="record.crm_customer_id">
          <h2 class="sec-title">相关信息</h2>
          <div class="overflow-hidden wt-glass">
            <button
              type="button"
              class="flex items-center w-full gap-3 px-4 py-3 text-left active:bg-[color:var(--pb-fill)]"
              @click="router.push({ name: 'customer-detail', params: { id: record.crm_customer_id } })"
            >
              <span class="flex-none size-5 text-[color:var(--pb-ink-2)] i-lucide-building-2" />
              <div class="flex-1 min-w-0">
                <div class="text-[15px] leading-5 text-[color:var(--pb-ink)]">客户档案</div>
                <div class="mt-0.5 text-[12px] leading-4 truncate text-[color:var(--pb-ink-3)]">
                  {{ record.customer_name || '查看客户详情' }}
                </div>
              </div>
              <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
            </button>
          </div>
        </template>

        <template v-if="items.length">
          <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-[color:var(--pb-ink-3)]">
            明细 {{ items.length }} 项
          </h2>
          <ul class="overflow-hidden wt-card">
            <li
              v-for="(it, i) in items"
              :key="it.id || i"
              class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-[color:var(--pb-sep)]"
            >
              <div class="flex-1 min-w-0">
                <div class="text-sm break-words text-[color:var(--pb-ink)]">{{ itemName(it) }}</div>
                <div v-if="itemQty(it) !== ''" class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">
                  ×{{ itemQty(it) }}{{ itemUnit(it) }}
                </div>
              </div>
              <span v-if="itemAmount(it)" class="flex-none text-sm text-[color:var(--pb-ink)]">
                {{ itemAmount(it) }}
              </span>
            </li>
          </ul>
        </template>

        <ul v-if="files.length" class="flex flex-col gap-2 mt-3">
          <li v-for="f in files" :key="f.id">
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

        <div class="h-6" />
      </DataState>
    </div>
  </div>
</template>
