<script setup>
import { ref, computed, reactive, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesStockEntriesStore } from 'dashboard/stores/mes/stockEntries';
import { useMesStockBalancesStore } from 'dashboard/stores/mes/stockBalances';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import { useMesRole } from 'dashboard/composables/useMesRole';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';

const store = useMesStockEntriesStore();
const balancesStore = useMesStockBalancesStore();
const warehousesStore = useMesWarehousesStore();
const { mesCan } = useMesRole();

const CONVERT_PURPOSES = 'CONVERT_TO_PRODUCT,CONVERT_TO_MATERIAL';
// 方向只有两个，但两处都要用（发起弹窗的选项、列表里的方向文案），所以收在一处。
const DIRECTIONS = [
  {
    value: 'TO_PRODUCT',
    label: '原料 → 成品',
    purpose: 'CONVERT_TO_PRODUCT',
    from: 'MATERIAL',
    fromLabel: '原料账',
    toLabel: '成品账',
  },
  {
    value: 'TO_MATERIAL',
    label: '成品 → 原料',
    purpose: 'CONVERT_TO_MATERIAL',
    from: 'PRODUCT',
    fromLabel: '成品账',
    toLabel: '原料账',
  },
];
const directionByPurpose = p => DIRECTIONS.find(d => d.purpose === p);

const canStock = computed(() => mesCan('stock'));
const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const converting = computed(() => store.getUIFlags.creatingItem);
const totalCount = computed(() => store.getMeta?.count || 0);

/* ---------------- 列表 ---------------- */
const ITEMS_PER_PAGE = 15; // 与后端 Mes::BaseController::RESULTS_PER_PAGE 一致
const page = ref(1);
const fetchList = () =>
  store.get({ purpose: CONVERT_PURPOSES, page: page.value });
watch(page, fetchList);

const num = v => Number(v || 0).toLocaleString();
const day = d => (d ? new Date(d).toLocaleString('sv').slice(0, 16) : '—');

// 一张转换单两行（一进一出、数量相等），列表每行只需摆一次商品和数量——
// 取增加的那一行：它带的就是「转成了什么、转了多少」。
const gainedItems = entry => {
  const dir = directionByPurpose(entry.purpose);
  const gains = dir?.value === 'TO_PRODUCT' ? 'PRODUCT' : 'MATERIAL';
  return (entry.stockEntryItems || []).filter(i => i.itemType === gains);
};
const itemsLabel = entry =>
  gainedItems(entry)
    .map(i => `${i.productName || i.crmProductId} × ${num(i.qty)}`)
    .join('、') || '—';

// 仓库名在前端映射：共享的 _mes_stock_entry partial 没出 to_warehouse_name，
// 为一个列去改它会让另外三个用它的页面每行多查一次库，而仓库列表本页已经加载了。
const warehouseName = id =>
  (warehousesStore.getRecords || []).find(w => w.id === id)?.name || '—';

const voidingId = ref(null);
const voidEntry = async entry => {
  voidingId.value = entry.id;
  try {
    await store.cancel(entry.id);
    useAlert(`${entry.entryNo} 已作废，两本账都冲回去了`);
    fetchList();
  } catch (error) {
    useAlert(error?.message || '作废失败');
  } finally {
    voidingId.value = null;
  }
};

/* ---------------- 发起转换 ---------------- */
// 先选方向和仓库，再把**来源那本账**上有货的商品列出来直接填数——
// 不另做一个商品搜索框：能转的本来就只有源账上有货的那些，列出来比让人去搜准得多。
const dialogRef = ref(null);
const form = reactive({ direction: 'TO_PRODUCT', warehouseId: '', remark: '' });
const q = ref('');
const qtyById = reactive({});
const sourceRows = ref([]);
const loadingSource = ref(false);

const currentDirection = computed(
  () => DIRECTIONS.find(d => d.value === form.direction) || DIRECTIONS[0]
);

const loadSource = async () => {
  sourceRows.value = [];
  Object.keys(qtyById).forEach(k => delete qtyById[k]);
  if (!form.warehouseId) return;

  loadingSource.value = true;
  try {
    const rows = await balancesStore.get({
      warehouse_id: form.warehouseId,
      item_type: currentDirection.value.from,
    });
    sourceRows.value = (rows || []).filter(
      r => r.crmProductId && Number(r.qty) > 0
    );
  } catch {
    sourceRows.value = [];
  } finally {
    loadingSource.value = false;
  }
};
watch(() => [form.direction, form.warehouseId], loadSource);

const filteredSource = computed(() => {
  const kw = q.value.trim().toLowerCase();
  if (!kw) return sourceRows.value;
  return sourceRows.value.filter(r =>
    `${r.sku || ''} ${r.productName || ''} ${r.specification || ''}`
      .toLowerCase()
      .includes(kw)
  );
});

// 填了数的那些行就是要转的。超过结存在这里先拦一道，后端过账还会再拦一次。
const pickedLines = computed(() =>
  sourceRows.value
    .map(r => ({ row: r, qty: Number(qtyById[r.crmProductId] || 0) }))
    .filter(l => l.qty > 0)
);
const overLines = computed(() =>
  pickedLines.value.filter(l => l.qty > Number(l.row.qty))
);
const canSubmit = computed(
  () =>
    !converting.value &&
    !!form.warehouseId &&
    pickedLines.value.length > 0 &&
    overLines.value.length === 0
);

const warehouseOptions = computed(() =>
  (warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  }))
);

const openDialog = () => {
  Object.assign(form, {
    direction: 'TO_PRODUCT',
    warehouseId: warehouseOptions.value[0]?.value || '',
    remark: '',
  });
  q.value = '';
  loadSource();
  dialogRef.value?.open();
};

const submit = async () => {
  if (!canSubmit.value) return;
  try {
    const entry = await store.convert({
      direction: form.direction,
      warehouse_id: form.warehouseId,
      remark: form.remark || undefined,
      lines: pickedLines.value.map(l => ({
        crm_product_id: l.row.crmProductId,
        qty: l.qty,
      })),
    });
    useAlert(`${entry.entryNo} 已转换并入账`);
    dialogRef.value?.close();
    page.value = 1;
    fetchList();
  } catch (error) {
    useAlert(error?.message || '转换失败');
  }
};

onMounted(() => {
  fetchList();
  warehousesStore.get();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1
        class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
      >
        原料成品转换
      </h1>
      <Button
        v-if="canStock"
        label="发起转换"
        color="iris"
        size="sm"
        icon="i-lucide-repeat"
        @click="openDialog"
      />
    </div>

    <div
      class="flex flex-wrap items-center gap-2 px-4 pb-3 sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <span class="text-label-small text-n-slate-11">
        同一个编码在系统里有原料账和成品账两本。采购入库记在原料账，销售出库从成品账扣——整机外购转卖这类货要先在这里换个身份才出得了货。数量在两本账之间平移，仓库和成本都不变。
      </span>
      <span class="ml-auto text-sm text-n-slate-11">
        {{ totalCount.toLocaleString() }} 条
      </span>
    </div>

    <HScrollButtons />

    <div
      class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8"
    >
      <table class="w-full text-sm">
        <thead
          class="sticky top-0 z-10 text-left bg-n-background text-n-slate-11"
        >
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium whitespace-nowrap">单号</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">方向</th>
            <th class="px-3 py-2 font-medium">商品</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">仓库</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">操作人</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">时间</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap" />
          </tr>
        </thead>
        <tbody>
          <tr v-if="isFetching">
            <td colspan="8" class="px-3 py-8 text-center text-n-slate-11">
              加载中…
            </td>
          </tr>
          <tr v-else-if="!records.length">
            <td colspan="8" class="px-3 py-8 text-center text-n-slate-11">
              还没有转换记录
            </td>
          </tr>
          <template v-else>
            <tr
              v-for="entry in records"
              :key="entry.id"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-12">
                {{ entry.entryNo }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ directionByPurpose(entry.purpose)?.label || entry.purpose }}
              </td>
              <td class="px-3 py-3 text-n-slate-12">{{ itemsLabel(entry) }}</td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ warehouseName(entry.toWarehouseId) }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ entry.ownerName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ day(entry.postedAt || entry.createdAt) }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                <span
                  :class="
                    entry.status === 'POSTED'
                      ? 'text-n-teal-11'
                      : 'text-n-slate-11'
                  "
                >
                  {{ entry.status === 'POSTED' ? '已入账' : '已作废' }}
                </span>
              </td>
              <td class="px-3 py-3 text-right whitespace-nowrap">
                <Button
                  v-if="canStock && entry.status === 'POSTED'"
                  label="作废"
                  color="ruby"
                  variant="faded"
                  size="xs"
                  :is-loading="voidingId === entry.id"
                  @click="voidEntry(entry)"
                />
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>

    <PaginationFooter
      v-if="totalCount > ITEMS_PER_PAGE"
      :current-page="page"
      :total-items="totalCount"
      :items-per-page="ITEMS_PER_PAGE"
      class="!bg-transparent before:!hidden"
      @update:current-page="page = $event"
    />

    <Dialog
      ref="dialogRef"
      width="3xl"
      confirm-button-color="iris"
      title="发起转换"
      description="选好方向和仓库，给要转的商品填上数量。确认后立即入账，填错了可以在列表里作废冲回。"
      :is-loading="converting"
      :disable-confirm-button="!canSubmit"
      confirm-button-label="确认转换"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-wrap items-center gap-2">
          <SelectCard v-model="form.direction" :options="DIRECTIONS" />
          <SelectCard
            v-model="form.warehouseId"
            :options="warehouseOptions"
            placeholder="选择仓库…"
          />
          <Input
            v-model="q"
            placeholder="搜编码 / 名称 / 规格"
            class="w-56"
            custom-input-class="reset-base h-9"
          />
          <span class="ml-auto text-label-small text-n-slate-11">
            已选 {{ pickedLines.length }} 个商品
          </span>
        </div>

        <div class="overflow-auto border rounded-lg max-h-80 border-n-weak">
          <table class="w-full text-sm">
            <thead class="sticky top-0 bg-n-alpha-1 text-n-slate-11">
              <tr class="border-b border-n-weak">
                <th class="px-3 py-2 font-medium text-left">编码</th>
                <th class="px-3 py-2 font-medium text-left">名称</th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  {{ currentDirection.fromLabel }}现有
                </th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  转多少
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loadingSource">
                <td colspan="4" class="px-3 py-6 text-center text-n-slate-11">
                  加载中…
                </td>
              </tr>
              <tr v-else-if="!filteredSource.length">
                <td colspan="4" class="px-3 py-6 text-center text-n-slate-11">
                  {{
                    form.warehouseId
                      ? `这个仓库的${currentDirection.fromLabel}上没有可转的货`
                      : '先选一个仓库'
                  }}
                </td>
              </tr>
              <template v-else>
                <tr
                  v-for="row in filteredSource"
                  :key="row.crmProductId"
                  class="border-b border-n-weak"
                >
                  <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
                    {{ row.sku || '—' }}
                  </td>
                  <td class="px-3 py-2 text-n-slate-12">
                    {{ row.productName || '—' }}
                    <span v-if="row.specification" class="text-n-slate-11">
                      · {{ row.specification }}
                    </span>
                  </td>
                  <td
                    class="px-3 py-2 text-right whitespace-nowrap text-n-slate-11"
                  >
                    {{ num(row.qty) }} {{ row.unit || '' }}
                  </td>
                  <td class="px-3 py-2 text-right whitespace-nowrap">
                    <Input
                      v-model="qtyById[row.crmProductId]"
                      type="number"
                      min="0"
                      :max="row.qty"
                      placeholder="0"
                      class="w-24 ml-auto"
                    />
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>

        <div v-if="overLines.length" class="text-label-small text-n-ruby-11">
          有 {{ overLines.length }} 个商品填的数超过了{{
            currentDirection.fromLabel
          }}现有数量
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">备注</label>
          <Input
            v-model="form.remark"
            placeholder="为什么要转，比如「客户单独要 80 台」"
            custom-input-class="reset-base h-9"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
