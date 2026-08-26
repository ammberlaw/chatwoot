<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMesStockBalancesStore } from 'dashboard/stores/mes/stockBalances';

const store = useMesStockBalancesStore();
const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);

const shortOnly = ref(false);
const fetch = () => store.get({ short: shortOnly.value ? 'true' : undefined });

const toggleShort = () => {
  shortOnly.value = !shortOnly.value;
  fetch();
};

onMounted(fetch);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-6 sm:py-4"
    >
      <h1 class="text-xl font-semibold text-n-slate-12">库存结存</h1>
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <input type="checkbox" :checked="shortOnly" @change="toggleShort" />
        只看短缺
      </label>
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="b in records"
            :key="b.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            :class="{ 'bg-n-ruby-2': b.isShort }"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ b.materialName || b.productName || '—' }}
              </span>
              <span
                v-if="b.isShort"
                class="px-1.5 py-0.5 text-xs rounded shrink-0 bg-n-ruby-3 text-n-ruby-11"
              >
                短缺
              </span>
              <span class="flex-1" />
            </div>
            <div class="flex flex-wrap gap-3 mt-2 text-xs text-n-slate-11">
              <span>编号：{{ b.materialNo || '—' }}</span>
              <span>仓库：{{ b.warehouseName || '—' }}</span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span :class="b.isShort ? 'text-n-ruby-11' : ''">
                结存：{{ b.qty }} {{ b.unit }}
              </span>
              <span :class="Number(b.reservedQty) > 0 ? 'text-n-amber-11' : ''">
                预占：{{ Number(b.reservedQty) > 0 ? b.reservedQty : '—' }}
              </span>
            </div>
            <div class="flex flex-wrap gap-3 mt-1 text-xs text-n-slate-11">
              <span>可用：{{ b.availableQty ?? b.qty }}</span>
              <span>安全库存：{{ b.safetyStock || '—' }}</span>
            </div>
          </div>
          <div v-if="!records.length" class="py-10 text-center text-n-slate-11">
            暂无库存结存。
          </div>
        </div>
        <table class="hidden w-full text-sm md:table">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">物料 / 成品</th>
              <th class="px-3 py-3 font-medium">编号</th>
              <th class="px-3 py-3 font-medium">仓库</th>
              <th class="px-3 py-3 font-medium">结存</th>
              <th class="px-3 py-3 font-medium">预占</th>
              <th class="px-3 py-3 font-medium">可用</th>
              <th class="px-3 py-3 font-medium">安全库存</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="b in records"
              :key="b.id"
              class="border-b border-n-weak"
              :class="{ 'bg-n-ruby-2': b.isShort }"
            >
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ b.materialName || b.productName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.materialNo || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.warehouseName || '—' }}
              </td>
              <td
                class="px-3 py-3 font-medium"
                :class="b.isShort ? 'text-n-ruby-11' : 'text-n-slate-12'"
              >
                {{ b.qty }} {{ b.unit }}
                <span v-if="b.isShort" class="ml-1 text-xs">短缺</span>
              </td>
              <td
                class="px-3 py-3"
                :class="
                  Number(b.reservedQty) > 0
                    ? 'text-n-amber-11'
                    : 'text-n-slate-10'
                "
              >
                {{ Number(b.reservedQty) > 0 ? b.reservedQty : '—' }}
              </td>
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ b.availableQty ?? b.qty }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.safetyStock || '—' }}
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
                暂无库存结存。
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </div>
</template>
