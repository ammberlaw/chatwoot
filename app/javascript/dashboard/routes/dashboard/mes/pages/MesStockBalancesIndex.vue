<script setup>
/* global axios */
import { ref, computed, reactive, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesStockBalancesStore } from 'dashboard/stores/mes/stockBalances';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { accountId } = useAccount();
const store = useMesStockBalancesStore();
const warehousesStore = useMesWarehousesStore();
const { mesCan } = useMesRole();

// store 走 camelcaseKeys(deep)：模板一律读驼峰（product_name 读出来是 undefined，
// 表现是名称/仓库整列空、类型永远显示「原料」）。
const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const canStock = computed(() => mesCan('stock'));

/* ---------------- 筛选 ---------------- */
const q = ref('');
const warehouseId = ref('');
const itemType = ref('');
const shortOnly = ref(false);
const page = ref(1);
const PER_PAGE = 50;

const fetch = () =>
  store.get({
    q: q.value || undefined,
    warehouse_id: warehouseId.value || undefined,
    item_type: itemType.value || undefined,
    short: shortOnly.value ? 'true' : undefined,
  });

// 结存接口不分页（一次返回全量），翻页在前端切——2000 行以内这样最省事，
// 也让「合计」不用再跑一次查询。
const paged = computed(() =>
  records.value.slice((page.value - 1) * PER_PAGE, page.value * PER_PAGE)
);
const shortCount = computed(() => records.value.filter(b => b.isShort).length);

const warehouseOptions = computed(() => [
  { value: '', label: '全部仓库' },
  ...(warehousesStore.getRecords || []).map(w => ({
    value: String(w.id),
    label: w.name,
  })),
]);
const ITEM_TYPE_OPTIONS = [
  { value: '', label: '全部类型' },
  { value: 'MATERIAL', label: '原料' },
  { value: 'PRODUCT', label: '成品' },
];

/* ---------------- 导出 ---------------- */
// 结存接口不分页（一次返回全量），records 就是全量——导的是**全部**结存，
// 不是前端切出来的那 50 行。导出跟着当前筛选走（仓库/类型/缺料/关键字）。
const exportList = () => {
  const typeLabel = value =>
    ITEM_TYPE_OPTIONS.find(o => o.value === value)?.label || value || '';
  exportRowsToExcel(
    {
      title: '库存结存',
      meta: [
        {
          label: '导出时间',
          value: new Date().toLocaleString('sv').slice(0, 16),
        },
        { label: '关键字', value: q.value || '（无）' },
        {
          label: '仓库',
          value:
            warehouseOptions.value.find(
              o => o.value === String(warehouseId.value)
            )?.label || '全部仓库',
        },
        { label: '类型', value: typeLabel(itemType.value) || '全部类型' },
        { label: '范围', value: shortOnly.value ? '只看缺料' : '全部' },
        { label: '行数', value: records.value.length },
      ],
      columns: [
        { label: '编码', key: 'sku' },
        { label: '名称', key: 'itemName' },
        { label: '规格', key: 'specification' },
        { label: '仓库', key: 'warehouseName' },
        { label: '类型', key: 'itemTypeLabel' },
        { label: '结存', key: 'qty', num: true },
        { label: '预占', key: 'reservedQty', num: true },
        { label: '可用', key: 'availableQty', num: true },
        { label: '单位', key: 'unit' },
      ],
      rows: records.value.map(row => ({
        ...row,
        itemName: row.productName || row.materialName,
        itemTypeLabel: typeLabel(row.itemType),
      })),
    },
    `库存结存_${new Date().toLocaleDateString('sv')}`
  );
};

let searchTimer = null;
watch(q, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    page.value = 1;
    fetch();
  }, 300);
});
watch([warehouseId, itemType, shortOnly], () => {
  page.value = 1;
  fetch();
});

/* ---------------- 期初库存导入 ---------------- */
// 期初是账的地基：先预检（只读）把「几个仓、多少成品/原料、哪些编码没档案」摆出来，
// 看清楚再按确认，不做上传即导入。
const importDialogRef = ref(null);
const fileInputRef = ref(null);
const pickedFile = ref(null);
const previewing = ref(false);
const importing = ref(false);
const preview = ref(null);
const importForm = reactive({
  createMissing: true,
  newProductLine: '',
  replace: false,
});

const PRODUCT_LINES = [
  { value: '', label: '选择产品线…' },
  { value: 'COMMERCIAL_DISPLAY', label: '商用显示' },
  { value: 'TABLET', label: '平板' },
];

const openImport = () => {
  pickedFile.value = null;
  preview.value = null;
  Object.assign(importForm, {
    createMissing: true,
    newProductLine: '',
    replace: false,
  });
  importDialogRef.value?.open();
};

const onPickFile = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  pickedFile.value = file;
  preview.value = null;
  previewing.value = true;
  try {
    const body = new FormData();
    body.append('file', file);
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/mes/stock_openings/preview`,
      body
    );
    preview.value = data.payload;
  } catch (error) {
    useAlert(error?.response?.data?.error || '文件读取失败');
    pickedFile.value = null;
  } finally {
    previewing.value = false;
  }
};

const missingCount = computed(() => preview.value?.missing_skus?.length || 0);
const needsProductLine = computed(
  () => missingCount.value > 0 && importForm.createMissing
);
const canImport = computed(
  () =>
    !!preview.value &&
    !importing.value &&
    (!needsProductLine.value || !!importForm.newProductLine)
);

const submitImport = async () => {
  if (!canImport.value) return;
  importing.value = true;
  try {
    const body = new FormData();
    body.append('file', pickedFile.value);
    body.append('create_missing_products', importForm.createMissing);
    body.append('new_product_line', importForm.newProductLine);
    body.append('replace', importForm.replace);
    const { data } = await axios.post(
      `/api/v1/accounts/${accountId.value}/mes/stock_openings`,
      body
    );
    const r = data.payload;
    useAlert(
      `期初导入完成：${r.rows} 行 / ${r.entries} 张单据` +
        (r.created_products ? `，新建档案 ${r.created_products} 条` : '') +
        (r.created_warehouses ? `，新建仓库 ${r.created_warehouses} 个` : '')
    );
    importDialogRef.value?.close();
    warehousesStore.get();
    fetch();
  } catch (error) {
    useAlert(error?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
};

onMounted(() => {
  fetch();
  warehousesStore.get();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      class="flex flex-wrap items-center justify-between gap-2 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">库存结存</h1>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，不挂库存写权限 -->
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          @click="exportList"
        />
        <Button
          v-if="canStock"
          label="导入期初库存"
          color="iris"
          size="sm"
          icon="i-lucide-upload"
          @click="openImport"
        />
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-2 px-4 pb-3 sm:px-6 [.theme-classic_&]:sm:!px-8">
      <Input
        v-model="q"
        placeholder="搜编码 / 名称 / 规格"
        class="w-64"
        custom-input-class="reset-base h-9"
      />
      <SelectCard v-model="warehouseId" :options="warehouseOptions" />
      <SelectCard v-model="itemType" :options="ITEM_TYPE_OPTIONS" />
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        <input
          type="checkbox"
          class="align-middle reset-base"
          :checked="shortOnly"
          @change="shortOnly = !shortOnly"
        />
        只看短缺
      </label>
      <!-- 条数在这儿给准确值：翻页条用的是紧凑格式，1803 会显示成「1k+」，看库存要精确数。
           不做数量合计——个/台/片/条/m/kg 加在一起没有意义。 -->
      <span class="ml-auto text-sm text-n-slate-11">
        {{ records.length.toLocaleString() }} 条
        <span v-if="shortCount" class="text-n-ruby-11">
          · 短缺 {{ shortCount }}
        </span>
      </span>
    </div>

    <HScrollButtons />
    <div class="flex-1 min-h-0 px-4 overflow-auto sm:px-6 [.theme-classic_&]:sm:!px-8">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <!-- 窄列一律 nowrap：规格那列一长，表头会被挤成「类 / 型」竖排。 -->
              <th class="px-3 py-3 font-medium whitespace-nowrap">编码</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap min-w-[152px]">
                名称
              </th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">规格</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">仓库</th>
              <th class="px-3 py-3 font-medium whitespace-nowrap">类型</th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                结存
              </th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                预占
              </th>
              <th class="px-3 py-3 font-medium text-right whitespace-nowrap">
                可用
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="b in paged"
              :key="b.id"
              class="border-b border-n-weak hover:bg-n-alpha-1"
              :class="{ 'bg-n-ruby-2': b.isShort }"
            >
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ b.sku || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-12">
                {{ b.productName || b.materialName || '—' }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">
                {{ b.specification || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap">
                {{ b.warehouseName || '—' }}
              </td>
              <td class="px-3 py-3 whitespace-nowrap text-n-slate-11">
                {{ b.itemType === 'PRODUCT' ? '成品' : '原料' }}
              </td>
              <td
                class="px-3 py-3 text-right whitespace-nowrap text-n-slate-12"
              >
                {{ Number(b.qty).toLocaleString() }}
                <span class="text-xs text-n-slate-10">{{ b.unit || '' }}</span>
              </td>
              <td class="px-3 py-3 text-right text-n-slate-11">
                {{ Number(b.reservedQty || 0).toLocaleString() }}
              </td>
              <td class="px-3 py-3 text-right text-n-slate-12">
                {{ Number(b.availableQty || 0).toLocaleString() }}
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
                没有库存记录。仓库里实际有货但系统是 0
                的，点右上角「导入期初库存」把实物库存搬进来。
              </td>
            </tr>
          </tbody>
        </table>
        <!-- 不满一页也显示：藏起来的话看不出是「没分页」还是「只有这些」。 -->
        <PaginationFooter
          v-if="records.length"
          :current-page="page"
          :total-items="records.length"
          :items-per-page="PER_PAGE"
          class="sticky bottom-0 z-10 mt-3"
          @update:current-page="page = $event"
        />
      </template>
    </div>

    <!-- 期初库存导入 -->
    <Dialog
      ref="importDialogRef"
      width="2xl"
      confirm-button-color="iris"
      title="导入期初库存"
      description="上传金蝶「库存查询表」。期初只加结存、记流水，不生成应付凭证、不绑生产订单。"
      :is-loading="importing"
      :disable-confirm-button="!canImport"
      confirm-button-label="确认导入"
      @confirm="submitImport"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">Excel 文件</label>
          <div class="flex items-center gap-3">
            <Button
              label="选择文件"
              color="slate"
              variant="faded"
              size="sm"
              icon="i-lucide-file-spreadsheet"
              @click="fileInputRef?.click()"
            />
            <span class="text-label-small text-n-slate-11">
              {{ previewing ? '读取中…' : pickedFile?.name || '未选择文件' }}
            </span>
          </div>
          <input
            ref="fileInputRef"
            type="file"
            accept=".xlsx"
            class="hidden"
            @change="onPickFile"
          />
        </div>

        <template v-if="preview">
          <div class="p-3 text-sm border rounded-lg border-n-weak bg-n-alpha-1">
            <div class="text-n-slate-12">
              共 {{ preview.total_rows }} 行 · 原料
              {{ preview.material_rows }} 行 · 成品
              {{ preview.finished_rows }} 行
            </div>
            <div
              v-if="preview.existing_opening_entries"
              class="mt-1 text-n-amber-11"
            >
              已有 {{ preview.existing_opening_entries }}
              张期初单。再导一次会重复加库存，需勾选下面的「替换上一批期初」。
            </div>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-label text-n-slate-12">仓库对应</span>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="w in preview.warehouses"
                :key="w.name"
                class="px-2 py-1 text-xs border rounded-md border-n-weak"
                :class="
                  w.will_create
                    ? 'text-n-amber-11 border-n-amber-6'
                    : 'text-n-slate-11'
                "
              >
                {{ w.name }} · {{ w.rows }} 行 →
                {{ w.will_create ? '新建仓库' : w.maps_to }}
              </span>
            </div>
          </div>

          <div v-if="missingCount" class="flex flex-col gap-2">
            <label
              class="inline-flex items-center gap-2 cursor-pointer text-label text-n-slate-12"
            >
              <input
                v-model="importForm.createMissing"
                type="checkbox"
                class="size-4"
              />
              自动建档（{{ missingCount }} 个编码产品档案里没有）
            </label>
            <div v-if="needsProductLine" class="flex flex-col gap-1">
              <span class="text-label-small text-n-slate-11">
                新建的档案归到哪条产品线 —— 留空的档案在领料选料里看不见，必须选
              </span>
              <div class="w-56">
                <SelectCard
                  v-model="importForm.newProductLine"
                  :options="PRODUCT_LINES"
                  block
                />
              </div>
            </div>
          </div>

          <label
            v-if="preview.existing_opening_entries"
            class="inline-flex items-center gap-2 cursor-pointer text-label text-n-slate-12"
          >
            <input
              v-model="importForm.replace"
              type="checkbox"
              class="size-4"
            />
            替换上一批期初（先作废旧期初单再导；期初货已被领用会整份回滚）
          </label>
        </template>
      </div>
    </Dialog>
  </div>
</template>
