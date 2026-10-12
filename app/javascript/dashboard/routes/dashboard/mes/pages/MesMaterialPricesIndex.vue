<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useMesRole } from 'dashboard/composables/useMesRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import MesMaterialPriceAPI from 'dashboard/api/mes/materialPrices';
import MesProductAPI from 'dashboard/api/mes/products';
import { exportRowsToExcel, fetchAllRows } from 'dashboard/helper/erpExcel';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
// 物料单价表：财务/采购维护的标准价，给生产任务单的成本核算兜底。
//
// 为什么需要它：算任务单的单台成本要给每颗料配价，但采购单只覆盖已经下过单的料。
// 这张表让财务把现有单价表一次贴进来，不用等采购把所有单补录一遍。
// 取价优先级（后端 Mes::MaterialPriceResolver）：本单采购价 > 本表标准价 > 最近采购价。
const { mesCan } = useMesRole();
const currentUser = useMapGetter('getCurrentUser');
// 口径在后端 AccountUser#can_view_material_cost?，前端只读这个标志
const canRead = computed(
  () => currentUser.value?.can_view_material_cost === true
);
const canWrite = computed(
  () => currentUser.value?.crm_finance === true || mesCan('purchase')
);

const ITEMS_PER_PAGE = 25;
const tab = ref('list'); // list | missing
const rows = ref([]);
const totalCount = ref(0);
const currentPage = ref(1);
const keyword = ref('');
const loading = ref(false);
const missingRows = ref([]);
const missingLoading = ref(false);

const money = micros => (micros ? fmtMoney(micros) : '—');
// 页面按「元」输入，落库按 micros：单价可能带小数（如 2.35）
const toMicros = yuan => Math.round(Number(yuan || 0) * 1_000_000);
const toYuan = micros => (micros ? String(micros / 1_000_000) : '');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await MesMaterialPriceAPI.get({
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

const loadMissing = async () => {
  missingLoading.value = true;
  try {
    const { data } = await MesMaterialPriceAPI.missing();
    missingRows.value = data?.payload || [];
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    missingLoading.value = false;
  }
};

const switchTab = next => {
  tab.value = next;
  if (next === 'missing' && !missingRows.value.length) loadMissing();
};

const search = () => {
  currentPage.value = 1;
  load();
};
const goPage = p => {
  currentPage.value = p;
  load();
};

// ── 新建 / 编辑 ───────────────────────────────────────────
const dialogRef = ref(null);
const editingId = ref(null);
const saving = ref(false);
const blankForm = () => ({ crmProductId: '', unitPrice: '', remark: '' });
const form = reactive(blankForm());
const { isDirty, markPristine } = useDirtyGuard(() => form);

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

const openCreate = (prefill = null) => {
  editingId.value = null;
  Object.assign(form, blankForm());
  if (prefill?.crm_product_id) {
    form.crmProductId = String(prefill.crm_product_id);
    productOptions.value = [
      {
        value: String(prefill.crm_product_id),
        label: `${prefill.sku} · ${prefill.name}${prefill.specification ? ` · ${prefill.specification}` : ''}`,
      },
    ];
  } else {
    loadProducts();
  }
  markPristine();
  dialogRef.value?.open();
};

const openEdit = row => {
  editingId.value = row.id;
  Object.assign(form, {
    crmProductId: String(row.crm_product_id),
    unitPrice: toYuan(row.unit_price_micros),
    remark: row.remark || '',
  });
  productOptions.value = [
    {
      value: String(row.crm_product_id),
      label: `${row.sku} · ${row.name}${row.specification ? ` · ${row.specification}` : ''}`,
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
    material_price: {
      crm_product_id: Number(form.crmProductId),
      unit_price_micros: toMicros(form.unitPrice),
      remark: form.remark,
    },
  };
  try {
    if (editingId.value) {
      await MesMaterialPriceAPI.update(editingId.value, payload);
    } else {
      await MesMaterialPriceAPI.create(payload);
    }
    useAlert(editingId.value ? '已保存' : '已新增');
    markPristine();
    dialogRef.value?.close();
    load();
    if (missingRows.value.length) loadMissing();
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
  if (!window.confirm(`删除「${row.sku} ${row.name}」的标准单价？`)) return;

  try {
    await MesMaterialPriceAPI.delete(row.id);
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
    const { data } = await MesMaterialPriceAPI.import(fd);
    importResult.value = data.payload;
    const r = data.payload;
    const tail = r.missing_count
      ? `，${r.missing_count} 条编码对不上商品档`
      : '';
    useAlert(`导入完成：新增 ${r.created} 条、更新 ${r.updated} 条${tail}`);
    load();
    if (missingRows.value.length) loadMissing();
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
  return `有 ${r.missing_count} 条物料编码在商品档里找不到，这些行没有导入：${r.missing_skus.join('、')}${more}`;
});

// 导出：⚠️ 全量——列表一页 25 条，导出重新向后端分页要完，不是导屏幕这一页。
const exporting = ref(false);
const exportList = async () => {
  exporting.value = true;
  try {
    const all = await fetchAllRows(params => MesMaterialPriceAPI.get(params), {
      q: keyword.value.trim() || undefined,
    });
    exportRowsToExcel(
      {
        title: '物料单价表',
        meta: [
          {
            label: '导出时间',
            value: new Date().toLocaleString('sv').slice(0, 16),
          },
          { label: '关键字', value: keyword.value.trim() || '（无）' },
          { label: '物料数', value: all.length },
        ],
        columns: [
          { label: '物料编码', key: 'sku' },
          { label: '物料名称', key: 'name' },
          { label: '规格型号', key: 'specification' },
          { label: '单位', key: 'unit' },
          { label: '单价', key: 'unit_price_micros', money: true },
          { label: '备注', key: 'remark' },
          { label: '最近修改', key: 'updated_by_name' },
        ],
        rows: all,
      },
      `物料单价表_${new Date().toLocaleDateString('sv')}`
    );
  } catch (error) {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};

onMounted(() => {
  if (canRead.value) load();
});
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div
      v-if="!canRead"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      物料单价含成本，只有财务、管理员和采购可以查看。
    </div>

    <template v-else>
      <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
        <h1 class="text-xl font-semibold text-n-slate-12">物料单价表</h1>
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
            @click="openCreate()"
          />
        </div>
      </div>

      <div class="px-4 pb-3 sm:px-6">
        <p class="text-label-small text-n-slate-11">
          财务 / 采购维护的物料标准单价，用于算生产任务单的单台成本。取价顺序：
          <b>本单采购价 → 本表标准价 → 最近一次采购价</b>
          ，都没有的行在任务单和导出里留空并标「无单价」，不会按 0 计。
        </p>
      </div>

      <div class="px-4 pb-3 sm:px-6">
        <div class="flex gap-1" data-tabbar="page">
          <button
            type="button"
            :aria-selected="tab === 'list'"
            @click="switchTab('list')"
          >
            单价表
          </button>
          <button
            type="button"
            :aria-selected="tab === 'missing'"
            @click="switchTab('missing')"
          >
            缺价清单
          </button>
        </div>
      </div>

      <!-- 单价表 -->
      <template v-if="tab === 'list'">
        <div class="flex flex-wrap items-center gap-2 px-4 pb-3 sm:px-6">
          <input
            v-model="keyword"
            placeholder="搜物料编码 / 名称 / 规格"
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
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  物料编码
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  物料名称
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  规格型号
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">单位</th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  单价
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">备注</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  最近修改
                </th>
                <th class="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in rows"
                :key="row.id"
                class="border-b border-n-weak hover:bg-n-alpha-1"
              >
                <td class="px-3 py-2 font-mono">{{ row.sku }}</td>
                <td class="px-3 py-2">{{ row.name }}</td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ row.specification }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">{{ row.unit }}</td>
                <td class="px-3 py-2 text-right tabular-nums">
                  {{ money(row.unit_price_micros) }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">{{ row.remark }}</td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ row.updated_by_name }}
                </td>
                <td class="px-3 py-2 text-right whitespace-nowrap">
                  <Button
                    v-if="canWrite"
                    label="编辑"
                    variant="ghost"
                    color="slate"
                    size="xs"
                    @click="openEdit(row)"
                  />
                  <Button
                    v-if="canWrite"
                    label="删除"
                    variant="ghost"
                    color="ruby"
                    size="xs"
                    @click="remove(row)"
                  />
                </td>
              </tr>
              <tr v-if="!rows.length && !loading">
                <td colspan="8" class="px-3 py-10 text-center text-n-slate-11">
                  还没有单价。点右上角「导入 Excel」把现有单价表贴进来。
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <PaginationFooter
          v-if="totalCount > ITEMS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalCount"
          :items-per-page="ITEMS_PER_PAGE"
          class="px-4 py-3 sm:px-6"
          @update:current-page="goPage"
        />
      </template>

      <!-- 缺价清单 -->
      <template v-else>
        <div class="px-4 pb-3 sm:px-6">
          <p class="text-label-small text-n-slate-11">
            生产任务单用到、但三级价源都查不到价的物料，按被多少张任务单用到排序。
            先补上面几条，成本覆盖率涨得最快。
          </p>
        </div>
        <HScrollButtons />
        <div class="flex-1 px-4 overflow-auto sm:px-6">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11 border-b border-n-weak">
                <th class="px-3 py-2 font-medium">物料编码</th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  物料名称
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">
                  规格型号
                </th>
                <th class="px-3 py-2 font-medium whitespace-nowrap">单位</th>
                <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                  被几张单用到
                </th>
                <th class="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in missingRows"
                :key="row.sku"
                class="border-b border-n-weak hover:bg-n-alpha-1"
              >
                <td class="px-3 py-2 font-mono">{{ row.sku }}</td>
                <td class="px-3 py-2">{{ row.name }}</td>
                <td class="px-3 py-2 text-n-slate-11">
                  {{ row.specification }}
                </td>
                <td class="px-3 py-2 text-n-slate-11">{{ row.unit }}</td>
                <td class="px-3 py-2 text-right tabular-nums">
                  {{ row.bom_count }}
                </td>
                <td class="px-3 py-2 text-right">
                  <Button
                    v-if="canWrite && row.crm_product_id"
                    label="补单价"
                    variant="ghost"
                    color="slate"
                    size="xs"
                    @click="openCreate(row)"
                  />
                  <span
                    v-else-if="canWrite"
                    class="text-label-small text-n-slate-11"
                  >
                    商品档里没这个编码
                  </span>
                </td>
              </tr>
              <tr v-if="!missingRows.length && !missingLoading">
                <td colspan="6" class="px-3 py-10 text-center text-n-slate-11">
                  所有用料都能取到价。
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </template>

    <Dialog
      ref="dialogRef"
      :title="editingId ? '编辑物料单价' : '新增物料单价'"
      :dirty="isDirty"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      confirm-button-label="保存"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div>
          <label class="block mb-1 text-label text-n-slate-12">物料</label>
          <ComboBox
            v-model="form.crmProductId"
            :options="productOptions"
            :disabled="!!editingId"
            placeholder="搜物料编码 / 名称"
            @search="loadProducts"
          />
          <p v-if="editingId" class="mt-1 text-label-small text-n-slate-11">
            物料不可改——换编码等于换一条记录，删掉重建更清楚。
          </p>
        </div>
        <Input
          v-model="form.unitPrice"
          label="单价（元）"
          type="number"
          placeholder="如 2.35"
        />
        <Input v-model="form.remark" label="备注" placeholder="选填" />
      </div>
    </Dialog>
  </div>
</template>
