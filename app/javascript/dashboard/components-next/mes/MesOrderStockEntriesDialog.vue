<script setup>
import { ref, computed } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MesStockEntryAPI from 'dashboard/api/mes/stockEntries';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const dialog = ref(null);
const order = ref(null);
const entries = ref([]);
const loading = ref(false);
const error = ref(false);
const page = ref(1);
const total = ref(0);
const pageSize = 15;
const statuses = { DRAFT: '草稿', POSTED: '已过账', CANCELLED: '已取消' };

// 「更多明细」：这张生产订单采购了哪些料、各到了多少、还差多少。
// 上面按入库单分组只答得了「这次收了什么」——而同一样料常常分几次到
// （A80 外壳那张单实收 42，累计其实到了 1000），只看单次会以为缺料。
const arrivals = ref([]);
const arrivalsOpen = ref(false);
const arrivalsLoaded = ref(false);
const arrivalsLoading = ref(false);
const arrivalsError = ref(false);

const loadArrivals = async () => {
  if (arrivalsLoaded.value || arrivalsLoading.value) return;
  arrivalsLoading.value = true;
  arrivalsError.value = false;
  try {
    const { data } = await MesProductionOrderAPI.arrivals(order.value.id);
    arrivals.value = camelcaseKeys(data.payload || [], { deep: true });
    arrivalsLoaded.value = true;
  } catch {
    // 别把请求失败显示成「没有明细」——那是两件事，后者会让人以为采购还没下单
    // （2026-11-10：接口 500，界面却说「这张单还没有关联的采购明细」）。
    arrivals.value = [];
    arrivalsError.value = true;
  } finally {
    arrivalsLoading.value = false;
  }
};

const retryArrivals = () => {
  arrivalsLoaded.value = false;
  loadArrivals();
};

const toggleArrivals = () => {
  arrivalsOpen.value = !arrivalsOpen.value;
  if (arrivalsOpen.value) loadArrivals();
};

const arrivalsDone = computed(
  () => arrivals.value.filter(r => Number(r.shortage) <= 0).length
);
const load = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await MesStockEntryAPI.get({
      purpose: 'MATERIAL_RECEIPT',
      production_order_id: order.value.id,
      page: page.value,
    });
    entries.value = camelcaseKeys(data.payload, { deep: true });
    total.value = Number(data.meta.count);
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
const open = po => {
  order.value = po;
  page.value = 1;
  entries.value = [];
  arrivals.value = [];
  arrivalsOpen.value = false;
  arrivalsLoaded.value = false;
  arrivalsError.value = false;
  dialog.value.open();
  load();
};
const turnPage = delta => {
  page.value += delta;
  load();
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    overflow-y-auto
    :show-confirm-button="false"
    cancel-button-label="关闭"
    :title="`原料入库单 · ${order?.orderNo || ''}`"
  >
    <p v-if="loading" class="py-8 text-center text-label text-n-slate-11">
      加载中…
    </p>
    <div v-else-if="error" class="py-6 text-center">
      <p class="mb-3 text-label text-n-slate-11">入库单加载失败</p>
      <Button label="重试" size="sm" @click="load" />
    </div>
    <p
      v-else-if="!entries.length"
      class="py-8 text-center text-label text-n-slate-11"
    >
      该订单暂无原料入库单
    </p>
    <div v-else class="flex flex-col gap-5">
      <section
        v-for="entry in entries"
        :key="entry.id"
        class="p-5 border border-n-weak rounded-2xl"
      >
        <div class="flex items-center justify-between gap-3 mb-4">
          <h2 class="text-heading-2 font-semibold text-n-slate-12">
            {{ entry.entryNo }}
          </h2>
          <span class="text-label-small text-n-slate-11">{{
            statuses[entry.status] || entry.status
          }}</span>
        </div>
        <div
          class="grid grid-cols-2 gap-3 mb-4 text-label-small text-n-slate-11"
        >
          <span>采购单：{{ entry.purchaseOrderNo || '—' }}</span>
          <span>收货人：{{ entry.receivedByName || '—' }}</span>
          <span>制单人：{{ entry.ownerName || '—' }}</span>
          <span
            >过账时间：{{
              entry.postedAt ? new Date(entry.postedAt).toLocaleString() : '—'
            }}</span
          >
        </div>
        <HScrollButtons />
        <div class="overflow-x-auto">
          <table class="w-full text-label-small text-left">
            <thead class="bg-n-alpha-1 text-n-slate-11">
              <tr>
                <th class="p-3 whitespace-nowrap">物料 / 编码</th>
                <th class="p-3 text-right whitespace-nowrap">应收</th>
                <th class="p-3 text-right whitespace-nowrap">实收</th>
                <th class="p-3 whitespace-nowrap">单位</th>
                <th class="p-3 whitespace-nowrap">备注</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in entry.stockEntryItems"
                :key="item.id"
                class="border-b border-n-weak"
              >
                <td class="p-3">
                  <strong class="block text-n-slate-12">{{
                    item.materialName || item.productName
                  }}</strong
                  ><span class="text-n-slate-10">{{ item.materialNo }}</span>
                </td>
                <td class="p-3 text-right tabular-nums">{{ item.qty }}</td>
                <td class="p-3 text-right tabular-nums">
                  {{ item.receivedQty ?? item.qty }}
                </td>
                <td class="p-3">{{ item.unit }}</td>
                <td class="p-3">{{ item.remark || '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div v-if="entry.receipts?.length" class="flex flex-wrap gap-3 mt-4">
          <a
            v-for="file in entry.receipts"
            :key="file.id"
            :href="file.url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-label-small text-n-iris-11 underline"
            >{{ file.filename }}</a
          >
        </div>
        <p v-if="entry.remark" class="mt-4 text-label-small text-n-slate-11">
          备注：{{ entry.remark }}
        </p>
      </section>
      <!-- 更多明细：按料号合并的到料全貌。上面按入库单分组答不了「料齐了没」。 -->
      <section class="border border-n-weak rounded-2xl">
        <button
          type="button"
          class="reset-base flex w-full items-center justify-between gap-3 px-5 py-3 text-left hover:bg-n-alpha-1"
          @click="toggleArrivals"
        >
          <span class="text-heading-3 text-n-slate-12">更多明细</span>
          <span
            class="flex items-center gap-2 text-label-small text-n-slate-11"
          >
            <span v-if="arrivalsLoaded">
              {{ arrivalsDone }} / {{ arrivals.length }} 种已齐
            </span>
            <span>{{ arrivalsOpen ? '收起' : '展开' }}</span>
          </span>
        </button>
        <div v-if="arrivalsOpen" class="px-5 pb-5">
          <p
            v-if="arrivalsLoading"
            class="py-4 text-center text-label-small text-n-slate-11"
          >
            加载中…
          </p>
          <div v-else-if="arrivalsError" class="py-4 text-center">
            <p class="mb-2 text-label-small text-n-slate-11">明细加载失败</p>
            <Button
              label="重试"
              size="sm"
              variant="outline"
              @click="retryArrivals"
            />
          </div>
          <p
            v-else-if="!arrivals.length"
            class="py-4 text-center text-label-small text-n-slate-11"
          >
            这张单还没有关联的采购明细
          </p>
          <div v-else class="overflow-x-auto">
            <table class="w-max min-w-full text-label-small text-left">
              <thead class="bg-n-alpha-1 text-n-slate-11">
                <tr>
                  <th class="p-3 whitespace-nowrap">物料 / 编码</th>
                  <th class="p-3 whitespace-nowrap">规格型号</th>
                  <th class="p-3 text-right whitespace-nowrap">采购量</th>
                  <th class="p-3 text-right whitespace-nowrap">已到料</th>
                  <th class="p-3 text-right whitespace-nowrap">还差</th>
                  <th class="p-3 whitespace-nowrap">单位</th>
                  <th class="p-3 whitespace-nowrap">采购单</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in arrivals"
                  :key="row.code || row.crmProductId"
                  class="border-b border-n-weak"
                >
                  <td class="p-3">
                    <strong class="block text-n-slate-12 whitespace-nowrap">{{
                      row.name || '—'
                    }}</strong>
                    <span class="text-n-slate-10">{{ row.code || '—' }}</span>
                  </td>
                  <td class="p-3 max-w-[16rem] truncate text-n-slate-11">
                    {{ row.specification || '—' }}
                  </td>
                  <td class="p-3 text-right tabular-nums">{{ row.qty }}</td>
                  <td class="p-3 text-right tabular-nums">
                    {{ row.receivedQty }}
                  </td>
                  <td
                    class="p-3 text-right tabular-nums"
                    :class="
                      Number(row.shortage) > 0
                        ? 'text-n-ruby-11 font-medium'
                        : 'text-n-slate-10'
                    "
                  >
                    {{ Number(row.shortage) > 0 ? row.shortage : '已齐' }}
                  </td>
                  <td class="p-3 whitespace-nowrap">{{ row.unit || '—' }}</td>
                  <td class="p-3 whitespace-nowrap text-n-slate-11">
                    {{ (row.poNos || []).join('、') || '—' }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
      <div class="flex items-center justify-end gap-3">
        <Button
          label="上一页"
          variant="ghost"
          size="sm"
          :disabled="page === 1"
          @click="turnPage(-1)"
        />
        <span class="text-label-small text-n-slate-11"
          >{{ page }} / {{ Math.max(1, Math.ceil(total / pageSize)) }}</span
        >
        <Button
          label="下一页"
          variant="ghost"
          size="sm"
          :disabled="page * pageSize >= total"
          @click="turnPage(1)"
        />
      </div>
    </div>
  </Dialog>
</template>
