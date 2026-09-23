<script setup>
import { ref, computed, onMounted } from 'vue';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchMyTarget } from '@/api/crm';
import { useTargetRows } from '@/composables/useTargetRows';
import { money } from '@/utils/format';

defineOptions({ name: 'MyTargetPage' });

const months = ref([]);
const year = ref(new Date().getFullYear());
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

const { rows, quarter, pct, barClass, nowYear, nowMonth } = useTargetRows(months, year);

const quarterPct = computed(() => pct(quarter.value.actual, quarter.value.base));

// 只列有动静的月份，空月份堆 12 行没意义
const visibleRows = computed(() => rows.value.filter(r => r.hasActivity || !r.isFuture));

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchMyTarget(year.value);
    months.value = r.data?.months || [];
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const shiftYear = d => {
  year.value += d;
  load();
};

const fmtPct = p => (p == null ? '—' : `${Math.round(p)}%`);
const barWidth = p => `${Math.min(100, Math.max(2, p ?? 0))}%`;

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back title="我的目标" :subtitle="`${year} 年`">
      <template #actions>
        <button
          type="button"
          aria-label="上一年"
          class="grid rounded-full size-9 place-items-center text-[color:var(--pb-ink-2)] active:bg-[color:var(--pb-fill)]"
          @click="shiftYear(-1)"
        >
          <span class="size-5 i-lucide-chevron-left" />
        </button>
        <button
          type="button"
          aria-label="下一年"
          class="grid rounded-full size-9 place-items-center text-[color:var(--pb-ink-2)] active:bg-[color:var(--pb-fill)]"
          :disabled="year >= nowYear"
          :class="year >= nowYear ? 'opacity-30' : ''"
          @click="shiftYear(1)"
        >
          <span class="size-5 i-lucide-chevron-right" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!months.length"
        :stale-at="staleAt"
        empty-text="这一年还没有目标数据"
        @retry="load"
      >
        <!-- 本季度整体（结转按季度清零，所以季度才是结算口径）-->
        <div class="p-4 wt-card">
          <div class="flex items-baseline justify-between">
            <span class="text-xs font-medium text-[color:var(--pb-ink-2)]">
              第 {{ quarter.index }} 季度至今
            </span>
            <span class="text-sm font-semibold text-[color:var(--pb-ink)]">
              {{ fmtPct(quarterPct) }}
            </span>
          </div>
          <div class="h-2 mt-2 overflow-hidden rounded-full bg-[color:var(--pb-fill)]">
            <div
              class="h-full rounded-full"
              :class="barClass(quarterPct)"
              :style="{ width: barWidth(quarterPct) }"
            />
          </div>
          <p class="mt-2 text-xs text-[color:var(--pb-ink-3)]">
            {{ money(quarter.actual) }} / {{ money(quarter.base) }}
          </p>
        </div>

        <p class="mt-3 text-xs text-[color:var(--pb-ink-3)]">未完成结转下月、每季度清零</p>

        <ul class="flex flex-col gap-2 mt-2">
          <li
            v-for="r in visibleRows"
            :key="r.month"
            class="p-3 wt-card"
            :class="r.month === nowMonth && year === nowYear ? 'ring-1 ring-[color:var(--pb-ink)]' : ''"
          >
            <div class="flex items-baseline justify-between">
              <span class="text-sm font-medium text-[color:var(--pb-ink)]">{{ r.month + 1 }} 月</span>
              <span class="text-sm font-semibold text-[color:var(--pb-ink)]">
                {{ fmtPct(pct(r.actualAmount, r.effAmount)) }}
              </span>
            </div>
            <div class="h-1.5 mt-2 overflow-hidden rounded-full bg-[color:var(--pb-fill)]">
              <div
                class="h-full rounded-full"
                :class="barClass(pct(r.actualAmount, r.effAmount))"
                :style="{ width: barWidth(pct(r.actualAmount, r.effAmount)) }"
              />
            </div>
            <div class="flex items-baseline justify-between mt-2">
              <span class="text-xs text-[color:var(--pb-ink-3)]">
                {{ money(r.actualAmount) }} / {{ money(r.effAmount) }}
              </span>
              <span
                v-if="!r.isFuture && r.carryAmount !== 0"
                class="text-xs"
                :class="r.carryAmount > 0 ? 'text-[color:var(--pb-accent)]' : 'text-[color:var(--pb-ink)]'"
              >
                {{ r.carryAmount > 0 ? '上月缺口' : '上月结余' }}
                {{ money(Math.abs(r.carryAmount)) }}
              </span>
            </div>
            <p v-if="r.isFuture" class="mt-1 text-xs text-[color:var(--pb-ink-3)]">
              该月未开始 · 仅显示基础目标
            </p>
          </li>
        </ul>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
