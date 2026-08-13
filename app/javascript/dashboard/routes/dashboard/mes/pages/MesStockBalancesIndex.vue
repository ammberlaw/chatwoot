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
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">库存结存</h1>
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <input type="checkbox" :checked="shortOnly" @change="toggleShort" />
        只看短缺
      </label>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
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
    </div>
  </div>
</template>
