<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import { useTiktokProfitRecordsStore } from 'dashboard/stores/tiktok/profitRecords';
import Button from 'dashboard/components-next/button/Button.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

// TikTok 出库利润表：按 店铺 × 型号 × 月份。负责人填，系统自动算毛利/净利润。
// 成本/佣金/税费/其它均 CNY 直填；已入账金额按币种换算 RMB。
const CURRENCIES = ['PHP', 'USD', 'EUR', 'CNY'];

const shopsStore = useTiktokShopsStore();
const deptStore = useTiktokDepartmentsStore();
const store = useTiktokProfitRecordsStore();

const { isAdmin, isCrmDeputyAdmin } = useCrmRole();
const canManageShops = computed(() => isAdmin.value || isCrmDeputyAdmin.value);

const shops = ref([]);
const departments = ref([]);
const records = ref([]);
const loading = ref(false);

const thisMonth = () => new Date().toISOString().slice(0, 7);
// 按「部门」筛选（原按店铺）：店铺归属部门，选部门即看该部门名下所有店铺的利润。
const filters = ref({ month: thisMonth(), departmentId: '' });

const shopName = id => shops.value.find(s => s.id === id)?.name || '—';
const shopDeptId = id =>
  shops.value.find(s => s.id === id)?.departmentId ?? null;

// 部门下拉：只列出「当前可见店铺」实际归属到的部门（非管理员自然只看到自己部门）。
const departmentOptions = computed(() => {
  const usedIds = new Set(shops.value.map(s => s.departmentId).filter(Boolean));
  return departments.value.filter(d => usedIds.has(d.id));
});
// 紫玻璃部门筛选下拉选项（含「全部部门」）
const departmentFilterOptions = computed(() => [
  { value: '', label: '全部部门' },
  ...departmentOptions.value.map(d => ({ value: d.id, label: d.name })),
]);

// 按部门过滤后的记录（部门为空=全部）；KPI/合计/表格都基于它。
const filteredRecords = computed(() => {
  if (!filters.value.departmentId) return records.value;
  return records.value.filter(
    r => shopDeptId(r.shopId) === filters.value.departmentId
  );
});
const num = v => Number(v || 0);
const cny = v =>
  `¥${num(v).toLocaleString('zh-CN', { maximumFractionDigits: 2 })}`;

const emptyForm = () => ({
  id: null,
  shopId: shops.value[0]?.id || '',
  productModel: '',
  statMonth: filters.value.month,
  periodNote: '',
  recordedQuantity: 0,
  platformNegative: 0,
  recordedAmount: 0,
  currency: 'PHP',
  costUnitPrice: 0,
  influencerCommission: 0,
  platformCommission: 0,
  tax: 0,
  otherCost: 0,
  otherCostNote: '',
  extraExpenses: [], // 其它费用清单：[{ name, amount }]
});
const form = ref(emptyForm());
const showForm = ref(false);
const isEdit = computed(() => form.value.id != null);

// 常用其它费用快捷项。
const EXPENSE_PRESETS = ['广告花费', '海外仓费用', '物流费', '退货损耗'];

const extraExpensesTotal = () =>
  (form.value.extraExpenses || []).reduce((s, e) => s + num(e.amount), 0);

const addExpense = (name = '') =>
  form.value.extraExpenses.push({ name, amount: 0 });

const removeExpense = i => form.value.extraExpenses.splice(i, 1);

// 录入预览（与后端同口径）
const preview = computed(() => {
  const f = form.value;
  const totalCost = num(f.costUnitPrice) * num(f.recordedQuantity);
  // 预览用当前币种粗略提示，实际 RMB 以保存时汇率为准；CNY 直接用原值。
  const amtCny = f.currency === 'CNY' ? num(f.recordedAmount) : null;
  const gross = amtCny == null ? null : amtCny - totalCost;
  const net =
    gross == null
      ? null
      : gross -
        num(f.influencerCommission) -
        num(f.platformCommission) -
        num(f.tax) -
        num(f.otherCost) -
        extraExpensesTotal();
  return { totalCost, gross, net };
});

const totals = computed(() =>
  filteredRecords.value.reduce(
    (t, r) => ({
      qty: t.qty + num(r.recordedQuantity),
      amountCny: t.amountCny + num(r.recordedAmountCny),
      cost: t.cost + num(r.totalCost),
      gross: t.gross + num(r.grossProfit),
      net: t.net + num(r.netProfit),
    }),
    { qty: 0, amountCny: 0, cost: 0, gross: 0, net: 0 }
  )
);

// V3 摘要辅助：毛利率百分比（毛利 / 入账RMB）。
const marginPct = (gross, amountCny) => {
  const base = num(amountCny);
  if (!base) return '—';
  return `${((num(gross) / base) * 100).toFixed(1)}%`;
};

// KPI 卡片配置（本月整体口径）。
const kpis = computed(() => [
  {
    key: 'net',
    label: '产品净利润',
    value: cny(totals.value.net),
    icon: 'i-lucide-trending-up',
    gradient: 'from-n-iris-3 to-n-iris-5',
    valueClass: totals.value.net < 0 ? 'text-n-ruby-11' : 'text-n-teal-11',
    sub: `毛利率 ${marginPct(totals.value.gross, totals.value.amountCny)}`,
  },
  {
    key: 'gross',
    label: '总毛利',
    value: cny(totals.value.gross),
    icon: 'i-lucide-hand-coins',
    gradient: 'from-n-iris-4 to-n-blue-4',
    valueClass: 'text-n-slate-12',
    sub: `售出 ${totals.value.qty} 台`,
  },
  {
    key: 'amount',
    label: '总入账RMB',
    value: cny(totals.value.amountCny),
    icon: 'i-lucide-wallet',
    gradient: 'from-n-blue-3 to-n-iris-5',
    valueClass: 'text-n-slate-12',
    sub: `${filteredRecords.value.length} 条记录`,
  },
  {
    key: 'cost',
    label: '售出总成本',
    value: cny(totals.value.cost),
    icon: 'i-lucide-package',
    gradient: 'from-n-iris-3 to-n-iris-6',
    valueClass: 'text-n-slate-12',
    sub: filters.value.month,
  },
]);

const loadRecords = async () => {
  loading.value = true;
  try {
    // 拉当月全部可见记录，部门过滤在前端做（filteredRecords）。
    records.value = await store.get({
      month: filters.value.month,
    });
  } catch (e) {
    useAlert(e?.message || '加载失败');
  } finally {
    loading.value = false;
  }
};

const openNew = () => {
  if (!shops.value.length) {
    useAlert(
      canManageShops.value
        ? '请先到「店铺设置」新增店铺'
        : '你所在部门还没有分配店铺，请联系管理员在「店铺设置」里分配'
    );
    return;
  }
  form.value = emptyForm();
  showForm.value = true;
};

const openEdit = r => {
  form.value = {
    id: r.id,
    shopId: r.shopId,
    productModel: r.productModel,
    statMonth: r.statMonth,
    periodNote: r.periodNote || '',
    recordedQuantity: r.recordedQuantity,
    platformNegative: r.platformNegative,
    recordedAmount: num(r.recordedAmount),
    currency: r.currency,
    costUnitPrice: num(r.costUnitPrice),
    influencerCommission: num(r.influencerCommission),
    platformCommission: num(r.platformCommission),
    tax: num(r.tax),
    otherCost: num(r.otherCost),
    otherCostNote: r.otherCostNote || '',
    extraExpenses: (r.extraExpenses || []).map(e => ({
      name: e.name || '',
      amount: num(e.amount),
    })),
  };
  showForm.value = true;
};

const submit = async () => {
  if (!form.value.shopId) return useAlert('请选择店铺');
  if (!form.value.productModel.trim()) return useAlert('请填写产品型号');
  const payload = { ...form.value };
  // 丢掉没填名称的空费用行。
  payload.extraExpenses = (form.value.extraExpenses || [])
    .filter(e => e.name && e.name.trim())
    .map(e => ({ name: e.name.trim(), amount: num(e.amount) }));
  try {
    if (isEdit.value) {
      await store.update(payload);
    } else {
      delete payload.id;
      await store.create(payload);
    }
    showForm.value = false;
    await loadRecords();
    return useAlert('已保存');
  } catch (e) {
    return useAlert(e?.message || '保存失败（同店同型号同月只能一条）');
  }
};

const remove = async r => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `删除 ${r.statMonth} · ${shopName(r.shopId)} · ${r.productModel}？`
    )
  ) {
    return;
  }
  try {
    await store.delete(r.id);
    await loadRecords();
    useAlert('已删除');
  } catch (e) {
    useAlert(e?.message || '删除失败');
  }
};

onMounted(async () => {
  try {
    [shops.value, departments.value] = await Promise.all([
      shopsStore.get(),
      deptStore.get(),
    ]);
  } catch (e) {
    /* 店铺/部门取不到不阻塞 */
  }
  await loadRecords();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="w-full px-4 py-4 mx-auto sm:px-8 sm:py-6 max-w-7xl">
      <!-- 头部 + 工具栏 -->
      <div class="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12">出库利润表</h1>
          <p class="mt-0.5 text-sm text-n-slate-11">
            本月经营摘要，明细可点行内「编辑」查看全部 17 项。
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <MonthPicker
            v-model="filters.month"
            trigger-class="w-full sm:w-40 h-10"
            :clearable="false"
            @change="loadRecords"
          />
          <SelectCard
            v-model="filters.departmentId"
            :options="departmentFilterOptions"
            trigger-class="w-full sm:w-40 h-10"
          />
          <Button
            color="iris"
            icon="i-lucide-plus"
            label="新增"
            class="shrink-0"
            @click="openNew"
          />
        </div>
      </div>

      <!-- KPI 摘要卡 -->
      <div class="grid grid-cols-1 gap-4 mb-6 sm:grid-cols-2 xl:grid-cols-4">
        <div
          v-for="kpi in kpis"
          :key="kpi.key"
          class="flex flex-col justify-between p-5 shadow-sm rounded-2xl bg-gradient-to-br min-h-[8.5rem]"
          :class="kpi.gradient"
        >
          <div class="flex items-center justify-between">
            <span
              class="flex items-center justify-center rounded-lg size-9 bg-n-solid-1/70 text-n-iris-11"
            >
              <span class="size-5" :class="kpi.icon" />
            </span>
          </div>
          <div class="mt-3">
            <p class="text-sm text-n-slate-11">{{ kpi.label }}</p>
            <p class="text-2xl font-bold" :class="kpi.valueClass">
              {{ kpi.value }}
            </p>
            <p class="mt-0.5 text-xs text-n-slate-11">{{ kpi.sub }}</p>
          </div>
        </div>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <!-- 精简明细表 -->
      <template v-else>
        <!-- 手机卡片列表 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="r in filteredRecords"
            :key="r.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openEdit(r)"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">
                {{ r.productModel }}
              </span>
              <span class="flex-1" />
              <span
                class="shrink-0 text-xs font-medium tabular-nums"
                :class="
                  num(r.netProfit) < 0 ? 'text-n-ruby-11' : 'text-n-teal-11'
                "
              >
                {{ cny(r.netProfit) }}
              </span>
              <Button
                variant="ghost"
                color="slate"
                size="xs"
                icon="i-lucide-pencil"
                class="shrink-0"
                @click.stop="openEdit(r)"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                class="shrink-0"
                @click.stop="remove(r)"
              />
            </div>
            <div class="mt-1 text-xs text-n-slate-11 truncate">
              {{ r.shopName || shopName(r.shopId) }}
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-1.5 text-xs text-n-slate-11"
            >
              <span>数量：{{ r.recordedQuantity }}</span>
              <span>入账RMB：{{ cny(r.recordedAmountCny) }}</span>
              <span>售出总成本：{{ cny(r.totalCost) }}</span>
              <span>总毛利：{{ cny(r.grossProfit) }}</span>
              <span
                >毛利率：{{
                  marginPct(r.grossProfit, r.recordedAmountCny)
                }}</span
              >
            </div>
          </div>
          <div
            v-if="!filteredRecords.length"
            class="p-6 text-sm text-center border rounded-xl border-white/60 bg-n-solid-1/75 text-n-slate-10"
          >
            本月暂无利润记录，点右上角「新增」开始录入。
          </div>
          <div
            v-if="filteredRecords.length"
            class="p-3 border rounded-xl border-white/60 bg-n-alpha-1 font-medium text-n-slate-12"
          >
            <div class="flex items-center gap-2">
              <span>合计</span>
              <span class="flex-1" />
              <span
                class="text-xs tabular-nums"
                :class="totals.net < 0 ? 'text-n-ruby-11' : 'text-n-teal-11'"
              >
                {{ cny(totals.net) }}
              </span>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-1.5 text-xs text-n-slate-11"
            >
              <span>数量：{{ totals.qty }}</span>
              <span>入账RMB：{{ cny(totals.amountCny) }}</span>
              <span>售出总成本：{{ cny(totals.cost) }}</span>
              <span>总毛利：{{ cny(totals.gross) }}</span>
              <span
                >毛利率：{{ marginPct(totals.gross, totals.amountCny) }}</span
              >
            </div>
          </div>
        </div>

        <div
          class="hidden md:block overflow-x-auto border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
        >
          <table class="w-full text-sm whitespace-nowrap">
            <thead>
              <tr class="text-xs text-left text-n-slate-11 bg-n-alpha-1">
                <th class="px-4 py-3 font-medium">店铺</th>
                <th class="px-4 py-3 font-medium">型号</th>
                <th class="px-4 py-3 font-medium text-right">数量</th>
                <th class="px-4 py-3 font-medium text-right">入账RMB</th>
                <th class="px-4 py-3 font-medium text-right">售出总成本</th>
                <th class="px-4 py-3 font-medium text-right">总毛利</th>
                <th class="px-4 py-3 font-medium text-right">净利润</th>
                <th class="px-4 py-3 font-medium text-right">毛利率</th>
                <th class="px-4 py-3 font-medium text-right">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in filteredRecords"
                :key="r.id"
                class="border-t border-n-weak hover:bg-n-alpha-1"
              >
                <td class="px-4 py-3 text-n-slate-12">
                  {{ r.shopName || shopName(r.shopId) }}
                </td>
                <td class="px-4 py-3 font-medium text-n-slate-12">
                  {{ r.productModel }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-11">
                  {{ r.recordedQuantity }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-12">
                  {{ cny(r.recordedAmountCny) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-11">
                  {{ cny(r.totalCost) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-12">
                  {{ cny(r.grossProfit) }}
                </td>
                <td
                  class="px-4 py-3 text-right tabular-nums font-medium"
                  :class="
                    num(r.netProfit) < 0 ? 'text-n-ruby-11' : 'text-n-teal-11'
                  "
                >
                  {{ cny(r.netProfit) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums text-n-slate-11">
                  {{ marginPct(r.grossProfit, r.recordedAmountCny) }}
                </td>
                <td class="px-4 py-3 text-right">
                  <div class="inline-flex items-center gap-0.5">
                    <Button
                      variant="ghost"
                      color="slate"
                      size="xs"
                      icon="i-lucide-pencil"
                      @click="openEdit(r)"
                    />
                    <Button
                      variant="ghost"
                      color="ruby"
                      size="xs"
                      icon="i-lucide-trash-2"
                      @click="remove(r)"
                    />
                  </div>
                </td>
              </tr>
              <tr v-if="!filteredRecords.length">
                <td colspan="9" class="px-4 py-12 text-center text-n-slate-10">
                  本月暂无利润记录，点右上角「新增」开始录入。
                </td>
              </tr>
            </tbody>
            <tfoot v-if="filteredRecords.length">
              <tr
                class="border-t-2 border-n-weak bg-n-alpha-1 font-medium text-n-slate-12"
              >
                <td class="px-4 py-3" colspan="2">合计</td>
                <td class="px-4 py-3 text-right tabular-nums">
                  {{ totals.qty }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums">
                  {{ cny(totals.amountCny) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums">
                  {{ cny(totals.cost) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums">
                  {{ cny(totals.gross) }}
                </td>
                <td
                  class="px-4 py-3 text-right tabular-nums"
                  :class="totals.net < 0 ? 'text-n-ruby-11' : 'text-n-teal-11'"
                >
                  {{ cny(totals.net) }}
                </td>
                <td class="px-4 py-3 text-right tabular-nums">
                  {{ marginPct(totals.gross, totals.amountCny) }}
                </td>
                <td class="px-4 py-3" />
              </tr>
            </tfoot>
          </table>
        </div>
      </template>
    </div>

    <!-- 录入/编辑弹窗（保留全部 17 项） -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showForm = false"
    >
      <div
        class="w-full max-w-[95vw] sm:max-w-2xl p-4 sm:p-6 overflow-y-auto max-h-[90vh] rounded-2xl bg-n-solid-1 shadow-xl"
      >
        <h2 class="mb-4 text-lg font-semibold text-n-slate-12">
          {{ isEdit ? '编辑利润记录' : '新增利润记录' }}
        </h2>

        <div class="grid grid-cols-2 sm:grid-cols-3 gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">店铺</span>
            <select
              v-model="form.shopId"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option v-for="s in shops" :key="s.id" :value="s.id">
                {{ s.name }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">产品型号</span>
            <input
              v-model="form.productModel"
              type="text"
              placeholder="如 K717"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">统计月份</span>
            <input
              v-model="form.statMonth"
              type="month"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">已入账数量（台）</span>
            <input
              v-model.number="form.recordedQuantity"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">已入账金额</span>
            <input
              v-model.number="form.recordedAmount"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">币种</span>
            <select
              v-model="form.currency"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option v-for="c in CURRENCIES" :key="c" :value="c">
                {{ c }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">出厂成本单价 (CNY)</span>
            <input
              v-model.number="form.costUnitPrice"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">达人佣金 (CNY)</span>
            <input
              v-model.number="form.influencerCommission"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">平台佣金 (CNY)</span>
            <input
              v-model.number="form.platformCommission"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">税费 (CNY)</span>
            <input
              v-model.number="form.tax"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">平台统计负数</span>
            <input
              v-model.number="form.platformNegative"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col col-span-2 gap-1">
            <span class="text-xs text-n-slate-11">统计时间备注（选填）</span>
            <input
              v-model="form.periodNote"
              type="text"
              placeholder="如 2月1日-7月20日"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </div>

        <!-- 其它费用（广告花费 / 海外仓费用 等，自由增减，计入净利润） -->
        <div class="mt-4">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-xs font-medium text-n-slate-11">
              其它费用（CNY）
            </span>
            <div class="flex items-center gap-1">
              <button
                v-for="p in EXPENSE_PRESETS"
                :key="p"
                class="px-2 py-0.5 text-xs rounded text-n-iris-11 bg-n-iris-3 hover:bg-n-iris-4"
                @click="addExpense(p)"
              >
                + {{ p }}
              </button>
            </div>
          </div>
          <div class="flex flex-col gap-1.5">
            <div
              v-for="(exp, i) in form.extraExpenses"
              :key="i"
              class="flex items-center gap-2"
            >
              <input
                v-model="exp.name"
                type="text"
                placeholder="费用名称（如 广告花费）"
                class="flex-1 h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
              />
              <input
                v-model.number="exp.amount"
                type="number"
                min="0"
                step="0.01"
                placeholder="金额"
                class="w-32 h-9 pl-2 !pr-8 text-sm rounded-lg shrink-0 reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                class="shrink-0"
                @click="removeExpense(i)"
              />
            </div>
            <button
              class="self-start px-2 py-1 text-xs rounded text-n-slate-11 hover:bg-n-alpha-2"
              @click="addExpense()"
            >
              + 添加其它费用
            </button>
          </div>
        </div>

        <!-- 预览 -->
        <div
          class="flex flex-wrap items-center gap-x-4 gap-y-1 px-3 py-2 mt-4 text-xs rounded-lg text-n-slate-11 bg-n-alpha-1"
        >
          <div class="flex items-center gap-1">
            <span>售出总成本</span>
            <b class="text-n-slate-12">{{ cny(preview.totalCost) }}</b>
          </div>
          <div v-if="preview.gross != null" class="flex items-center gap-1">
            <span>总毛利</span>
            <b class="text-n-slate-12">{{ cny(preview.gross) }}</b>
          </div>
          <div v-if="form.extraExpenses.length" class="flex items-center gap-1">
            <span>其它费用</span>
            <b class="text-n-slate-12">{{ cny(extraExpensesTotal()) }}</b>
          </div>
          <div v-if="preview.net != null" class="flex items-center gap-1">
            <span>净利润</span>
            <b class="text-n-slate-12">{{ cny(preview.net) }}</b>
          </div>
          <span class="text-n-slate-10">
            非 CNY 金额的 RMB 换算于保存时按实时汇率计算
          </span>
        </div>

        <div class="flex justify-end gap-2 mt-6">
          <Button
            variant="ghost"
            color="slate"
            label="取消"
            @click="showForm = false"
          />
          <Button color="iris" label="保存" @click="submit" />
        </div>
      </div>
    </div>
  </div>
</template>
