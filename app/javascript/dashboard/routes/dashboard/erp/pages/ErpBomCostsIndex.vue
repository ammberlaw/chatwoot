<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpBomCostAPI from 'dashboard/api/erp/bomCosts';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';
import MesProductAPI from 'dashboard/api/mes/products';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// BOM 成本表：按商品编码维护「人工费（生产人工）」和「制造费用」两个标准单价。
//
// 这张表直接喂给成本归集：成品入库过账后，Erp::CostRollupService 按
//   完工入库数量 × 人工费   → 生产人工
//   完工入库数量 × 制造费用 → 制造费用
// 归到销售订单上，和按领料算的材料成本一起构成毛利的成本侧。
// 所以改这里的数 = 改毛利，写权限收在 cost 能力域（出纳看得到、改不了）。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('cost'));

const ITEMS_PER_PAGE = 25;
const rows = ref([]);
const totalCount = ref(0);
const currentPage = ref(1);
const keyword = ref('');
const loading = ref(false);

const money = micros => (micros ? fmtMoney(micros) : '—');

// 点开一行看这个成品编码下的物料与料价。按需拉取——161 个编码各带几十行物料，
// 塞进列表接口一次响应就几兆。同一时间只展开一行，省得整页都是明细表。
const expanded = ref(null);
const materials = ref({ items: [] });
const materialsLoading = ref(false);
const materialTotal = computed(() =>
  materials.value.items.reduce((sum, m) => sum + Number(m.amount_micros || 0), 0)
);

const toggleMaterials = async row => {
  if (expanded.value === row.id) {
    expanded.value = null;
    return;
  }
  expanded.value = row.id;
  materials.value = { items: [] };
  materialsLoading.value = true;
  try {
    const { data } = await ErpBomCostAPI.materials(row.id);
    // 拉回来时用户可能已经点开别行了，丢弃过期响应
    if (expanded.value === row.id) materials.value = data.payload || { items: [] };
  } catch {
    if (expanded.value === row.id) materials.value = { items: [] };
  } finally {
    materialsLoading.value = false;
  }
};
// 页面按「元」输入，落库按 micros：整数分以下也要留得住（人工费可能是 1.5 元）
const toMicros = yuan => Math.round(Number(yuan || 0) * 1_000_000);
const toYuan = micros => (micros ? String(micros / 1_000_000) : '');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await ErpBomCostAPI.get({
      q: keyword.value.trim() || undefined,
      page: currentPage.value,
      per_page: ITEMS_PER_PAGE,
    });
    rows.value = data?.payload || [];
    totalCount.value = data?.meta?.count || 0;
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

const search = () => {
  currentPage.value = 1;
  load();
};
const goPage = p => {
  currentPage.value = p;
  load();
};

// ── 导出 ───────────────────────────────────────────
// ⚠️ 全量：列表一页 25 条，导出重新向后端分页要完，不是导屏幕这一页。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const all = await fetchAllRows(params => ErpBomCostAPI.get(params), {
      q: keyword.value.trim() || undefined,
    });
    exportRowsToExcel(
      {
        title: 'BOM 成本表',
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '关键字', value: keyword.value.trim() || '（无）' },
          { label: '产品数', value: all.length },
        ],
        columns: [
          { label: '商品编码', key: 'sku' },
          { label: '产品名称', key: 'product_name' },
          { label: '规格型号', key: 'specification' },
          { label: '人工费', key: 'process_fee_micros', money: true },
          { label: '制造费用', key: 'overhead_fee_micros', money: true },
          { label: '合计单价', key: 'unit_cost_micros', money: true },
          { label: '备注', key: 'remark' },
          { label: '最近修改', key: 'updated_by_name' },
        ],
        rows: all,
      },
      `BOM成本表_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

// ── 新建 / 编辑 ───────────────────────────────────────────
const dialogRef = ref(null);
const editingId = ref(null);
const saving = ref(false);
const blankForm = () => ({
  crmProductId: '',
  processFee: '',
  overheadFee: '',
  remark: '',
});
const form = reactive(blankForm());
const { isDirty, markPristine } = useDirtyGuard(() => form);

// 产品下拉：新建时才需要选，编辑态锁死（换商品编码等于换一条记录，容易误操作）
const productOptions = ref([]);
const loadProducts = async (q = '') => {
  try {
    const { data } = await MesProductAPI.get({
      q: q || undefined,
      per_page: 50,
    });
    productOptions.value = (data?.payload || []).map(p => ({
      value: String(p.id),
      label: `${p.sku} · ${p.name}${p.specification ? ` · ${p.specification}` : ''}`,
    }));
  } catch {
    productOptions.value = [];
  }
};

const openCreate = () => {
  editingId.value = null;
  Object.assign(form, blankForm());
  loadProducts();
  markPristine();
  dialogRef.value?.open();
};

const openEdit = row => {
  editingId.value = row.id;
  Object.assign(form, {
    crmProductId: String(row.crm_product_id),
    processFee: toYuan(row.process_fee_micros),
    overheadFee: toYuan(row.overhead_fee_micros),
    remark: row.remark || '',
  });
  productOptions.value = [
    {
      value: String(row.crm_product_id),
      label: `${row.sku} · ${row.product_name}${row.specification ? ` · ${row.specification}` : ''}`,
    },
  ];
  markPristine();
  dialogRef.value?.open();
};

const invalid = computed(() => !form.crmProductId);

const submit = async () => {
  if (invalid.value || saving.value) return;
  saving.value = true;
  const payload = {
    bom_cost: {
      crm_product_id: Number(form.crmProductId),
      process_fee_micros: toMicros(form.processFee),
      overhead_fee_micros: toMicros(form.overheadFee),
      remark: form.remark,
    },
  };
  try {
    if (editingId.value) await ErpBomCostAPI.update(editingId.value, payload);
    else await ErpBomCostAPI.create(payload);
    useAlert(editingId.value ? '已保存' : '已新增');
    markPristine();
    dialogRef.value?.close();
    load();
  } catch (e) {
    useAlert(
      e?.response?.data?.message || e?.response?.data?.error || '保存失败'
    );
  } finally {
    saving.value = false;
  }
};

const remove = async row => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`删除「${row.sku} ${row.product_name}」的加工成本标准？`))
    return;

  try {
    await ErpBomCostAPI.delete(row.id);
    useAlert('已删除');
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '删除失败');
  }
};

// ── Excel 导入 ───────────────────────────────────────────
const fileInputRef = ref(null);
const importing = ref(false);
const importResult = ref(null);

const onPickFile = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;

  importing.value = true;
  importResult.value = null;
  try {
    const fd = new FormData();
    fd.append('file', file);
    const { data } = await ErpBomCostAPI.import(fd);
    importResult.value = data.payload;
    const r = data.payload;
    useAlert(
      `导入完成：新增 ${r.created} 条、更新 ${r.updated} 条${r.missing_count ? `，${r.missing_count} 条编码对不上产品档案` : ''}`
    );
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
};

// 导入后「哪些编码没进去」拼成一句话：模板里插一长串表达式会被 prettier 折得很难看
const missingHint = computed(() => {
  const r = importResult.value;
  if (!r?.missing_count) return '';
  const more = r.missing_count > r.missing_skus.length ? ' …' : '';
  return `有 ${r.missing_count} 条商品编码在产品档案里找不到，这些行没有导入：${r.missing_skus.join('、')}${more}`;
});

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">BOM 成本表</h1>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，不挂写权限 -->
        <Button
          label="导出 Excel"
          variant="faded"
          color="slate"
          size="sm"
          :is-loading="exporting"
          @click="exportList"
        />
        <Button
          v-if="canWrite"
          label="导入 Excel"
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          icon="i-lucide-file-spreadsheet"
          :is-loading="importing"
          @click="fileInputRef?.click()"
        />
        <input
          ref="fileInputRef"
          type="file"
          accept=".xlsx"
          class="hidden"
          @change="onPickFile"
        />
        <Button
          v-if="canWrite"
          label="新增"
          color="iris"
          size="sm"
          @click="openCreate"
        />
      </div>
    </div>

    <div class="px-4 pb-3 sm:px-6">
      <p class="text-label-small text-n-slate-11">
        按商品编码维护人工费（生产人工）与制造费用的标准单价。成品入库过账后，系统按
        <b>完工入库数量 × 单价</b>
        自动归集到对应销售订单的成本里，和领料算出的材料成本一起算毛利。
      </p>
    </div>

    <div class="flex flex-wrap items-center gap-2 px-4 pb-3 sm:px-6">
      <input
        v-model="keyword"
        placeholder="搜商品编码 / 名称 / 规格"
        class="h-9 px-3 text-sm rounded-lg outline-none reset-base w-72 border border-n-weak bg-n-solid-1 text-n-slate-12"
        @keyup.enter="search"
      />
      <Button
        label="搜索"
        variant="outline"
        color="slate"
        size="sm"
        @click="search"
      />
      <span class="text-label-small text-n-slate-11">
        共 {{ totalCount }} 条
      </span>
    </div>

    <!-- 导入结果里对不上的编码单列出来：让人知道哪几行没进去，而不是只看到一个总数 -->
    <div
      v-if="missingHint"
      class="p-3 mx-4 mb-3 text-sm border rounded-lg sm:mx-6 border-n-amber-8 bg-n-amber-3 text-n-amber-11"
    >
      {{ missingHint }}
    </div>

    <HScrollButtons />
    <div class="flex-1 px-4 overflow-auto sm:px-6">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-2 font-medium whitespace-nowrap">商品编码</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">产品名称</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">规格型号</th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              人工费
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              制造费用
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              合计单价
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">备注</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">最近修改</th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <template v-for="row in rows" :key="row.id">
          <tr
            class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
            @click="toggleMaterials(row)"
          >
            <td class="px-3 py-2 font-medium text-n-slate-12">
              <span
                class="inline-block mr-1 size-3 align-middle text-n-slate-10"
                :class="expanded === row.id ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
              />{{ row.sku }}</td>
            <td class="px-3 py-2 text-n-slate-12">{{ row.product_name }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.specification || '—' }}
            </td>
            <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
              {{ money(row.process_fee_micros) }}
            </td>
            <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
              {{ money(row.overhead_fee_micros) }}
            </td>
            <td
              class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
            >
              {{ money(row.unit_cost_micros) }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.remark || '—' }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.updated_by_name || '—' }}
            </td>
            <td class="px-3 py-2 text-right whitespace-nowrap">
              <template v-if="canWrite">
                <Button
                  label="编辑"
                  variant="ghost"
                  size="sm"
                  @click="openEdit(row)"
                />
                <Button
                  label="删除"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="remove(row)"
                />
              </template>
            </td>
          </tr>
          <!-- 展开：这个成品编码下的物料与料价。
               生产上 161 个编码里只有 18 个真做过 BOM，所以没有的要明说
               「还没做 BOM」，摆一片空白会让人以为是没加载出来。 -->
          <tr v-if="expanded === row.id">
            <td colspan="9" class="px-3 py-2 bg-n-alpha-1">
              <div v-if="materialsLoading" class="text-xs text-n-slate-11">
                加载中…
              </div>
              <div v-else-if="!materials.items.length" class="text-xs text-n-slate-11">
                这个商品编码还没做过 BOM，所以没有物料清单。做了生产任务单之后这里就有了。
              </div>
              <template v-else>
                <div class="mb-1 text-xs text-n-slate-10">
                  来自 {{ materials.bom_no || 'BOM' }}
                  <span v-if="materials.base_qty">（基准用量 {{ materials.base_qty }}）</span>
                  <span v-if="!materials.is_default">· 非默认 BOM，仅供参考</span>
                </div>
                <table class="w-full text-xs">
                  <thead>
                    <tr class="text-left border-b text-n-slate-11 border-n-weak">
                      <th class="px-2 py-1 font-medium">物料编码</th>
                      <th class="px-2 py-1 font-medium">物料名称</th>
                      <th class="px-2 py-1 font-medium">规格</th>
                      <th class="px-2 py-1 font-medium text-right">用量</th>
                      <th class="px-2 py-1 font-medium text-right">单价</th>
                      <th class="px-2 py-1 font-medium text-right">金额</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(m, i) in materials.items" :key="`m-${i}`" class="border-b border-n-weak">
                      <td class="px-2 py-1 font-mono text-n-slate-12">{{ m.material_no || '—' }}</td>
                      <td class="px-2 py-1 text-n-slate-12">{{ m.material_name || '—' }}</td>
                      <td class="px-2 py-1 text-n-slate-11">{{ m.specification || '—' }}</td>
                      <td class="px-2 py-1 text-right tabular-nums">{{ m.qty }}{{ m.unit || '' }}</td>
                      <td class="px-2 py-1 text-right tabular-nums">{{ money(m.rate_micros) }}</td>
                      <td class="px-2 py-1 text-right tabular-nums text-n-slate-12">{{ money(m.amount_micros) }}</td>
                    </tr>
                    <tr class="font-medium">
                      <td class="px-2 py-1" colspan="5">材料合计</td>
                      <td class="px-2 py-1 text-right tabular-nums">{{ money(materialTotal) }}</td>
                    </tr>
                  </tbody>
                </table>
              </template>
            </td>
          </tr>
          </template>
          <tr v-if="!rows.length && !loading">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有维护加工成本标准。点右上角「导入
              Excel」批量导，或「新增」逐条加。
            </td>
          </tr>
        </tbody>
      </table>

      <PaginationFooter
        v-if="totalCount > ITEMS_PER_PAGE"
        :current-page="currentPage"
        :total-items="totalCount"
        :items-per-page="ITEMS_PER_PAGE"
        class="!bg-transparent before:!hidden"
        @update:current-page="goPage"
      />
    </div>

    <Dialog
      ref="dialogRef"
      :dismissible="false"
      width="2xl"
      confirm-button-color="iris"
      :title="editingId ? '编辑加工成本标准' : '新增加工成本标准'"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      confirm-button-label="保存"
      :dirty="isDirty"
      @confirm="submit"
      @save="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">
            商品编码 <span class="text-n-ruby-11">*</span>
          </label>
          <!-- 编辑态锁死：换商品编码等于换一条记录，改错了会把别的产品的标准覆盖掉 -->
          <ComboBox
            v-if="!editingId"
            v-model="form.crmProductId"
            :options="productOptions"
            use-api-results
            placeholder="搜商品编码 / 名称 / 规格"
            @search="loadProducts"
          />
          <div v-else class="text-sm h-9 flex items-center text-n-slate-11">
            {{ productOptions[0]?.label }}
          </div>
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">人工费（元/个）</label>
            <Input v-model="form.processFee" type="number" placeholder="0" />
            <span class="text-label-small text-n-slate-10">
              即生产人工，按完工入库数量计入成本
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-label text-n-slate-12">制造费用（元/个）</label>
            <Input v-model="form.overheadFee" type="number" placeholder="0" />
            <span class="text-label-small text-n-slate-10">
              同样按完工入库数量计入成本
            </span>
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">备注</label>
          <Input v-model="form.remark" placeholder="选填" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
