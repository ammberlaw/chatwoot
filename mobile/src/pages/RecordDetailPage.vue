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
          <h1 class="flex-1 text-base font-semibold leading-snug text-n-slate-12">
            {{ cfg.row(record).title }}
          </h1>
          <span
            v-if="cfg.statusLabels[record[cfg.statusKey]]"
            class="flex-none px-2 py-1 text-xs rounded-lg"
            :class="cfg.statusTone[record[cfg.statusKey]] || 'bg-n-alpha-1 text-n-slate-11'"
          >
            {{ cfg.statusLabels[record[cfg.statusKey]] }}
          </span>
        </div>

        <button
          v-if="record.crm_customer_id"
          type="button"
          class="mt-1 text-xs underline text-n-iris-11 underline-offset-2"
          @click="
            router.push({ name: 'customer-detail', params: { id: record.crm_customer_id } })
          "
        >
          查看客户档案
        </button>

        <div v-if="rows.length" class="mt-3 overflow-hidden wt-card">
          <div
            v-for="row in rows"
            :key="row.label"
            class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-n-weak"
          >
            <span class="flex-none w-20 text-xs text-n-slate-10">{{ row.label }}</span>
            <span class="flex-1 text-sm break-words whitespace-pre-line text-n-slate-12">
              {{ row.value }}
            </span>
          </div>
        </div>

        <template v-if="items.length">
          <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-n-slate-10">
            明细 {{ items.length }} 项
          </h2>
          <ul class="overflow-hidden wt-card">
            <li
              v-for="(it, i) in items"
              :key="it.id || i"
              class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-n-weak"
            >
              <div class="flex-1 min-w-0">
                <div class="text-sm break-words text-n-slate-12">{{ itemName(it) }}</div>
                <div v-if="itemQty(it) !== ''" class="mt-0.5 text-xs text-n-slate-10">
                  ×{{ itemQty(it) }}{{ itemUnit(it) }}
                </div>
              </div>
              <span v-if="itemAmount(it)" class="flex-none text-sm text-n-slate-12">
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
              class="flex items-center gap-3 p-3 wt-card active:bg-n-alpha-1"
            >
              <span class="flex-none size-4 text-n-slate-10 i-lucide-paperclip" />
              <span class="flex-1 text-sm truncate text-n-iris-11">{{ f.filename }}</span>
              <span class="flex-none text-xs text-n-slate-10">{{ kb(f.byte_size) }}</span>
            </a>
          </li>
        </ul>

        <div class="h-6" />
      </DataState>
    </div>
  </div>
</template>
