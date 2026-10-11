<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import { useTiktokSalesRecordsStore } from 'dashboard/stores/tiktok/salesRecords';
import Button from 'dashboard/components-next/button/Button.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

// TikTok 每日录入：一店一天一行。取消率/有效率由台数派生（后端算，前端只做录入预览）；
// 销售额换算 RMB 于录入时按实时汇率存快照。
const CURRENCIES = ['PHP', 'USD', 'EUR', 'CNY'];

const shopsStore = useTiktokShopsStore();
const recordsStore = useTiktokSalesRecordsStore();

// 仅管理员/副管理员能管理店铺；非管理员看不到店铺时提示改为「联系管理员分配」而非「去新增店铺」。
const { isAdmin, isCrmDeputyAdmin } = useCrmRole();
const canManageShops = computed(() => isAdmin.value || isCrmDeputyAdmin.value);

const shops = ref([]);
const records = ref([]);
const loading = ref(false);

const today = () => new Date().toISOString().slice(0, 10);
const thisMonth = () => today().slice(0, 7);

const filters = ref({ month: thisMonth(), shopId: '' });

const activeShops = computed(() => shops.value.filter(s => s.active));
// 紫玻璃店铺筛选下拉选项（含「全部店铺」）
const shopFilterOptions = computed(() => [
  { value: '', label: '全部店铺' },
  ...shops.value.map(s => ({ value: s.id, label: s.name })),
]);
const shopName = id => shops.value.find(s => s.id === id)?.name || '—';

const pct = v => (v == null ? '—' : `${(v * 100).toFixed(1)}%`);
const cny = v =>
  `¥${Number(v || 0).toLocaleString('zh-CN', { maximumFractionDigits: 0 })}`;

const emptyForm = () => ({
  id: null,
  saleDate: today(),
  shopId: activeShops.value[0]?.id || '',
  allianceLiveOrders: 0,
  allianceOrders: 0,
  productCardOrders: 0,
  merchantOrders: 0,
  totalOrders: 0,
  totalUnits: 0,
  salesAmount: 0,
  currency: 'PHP',
  cancelledUnits: 0,
  shippedUnits: 0,
  influencerUnits: 0,
  remark: '',
});
const form = ref(emptyForm());
const showForm = ref(false);
const isEdit = computed(() => form.value.id != null);

// 订单来源四拆分合计＝总订单（表单只读展示，保存时以此为准）。
const orderSourceTotal = computed(() => {
  const n = v => Number(v || 0);
  return (
    n(form.value.allianceLiveOrders) +
    n(form.value.allianceOrders) +
    n(form.value.productCardOrders) +
    n(form.value.merchantOrders)
  );
});

// 录入预览：与后端同口径（总台数为 0 时不显示）。
const previewCancelRate = computed(() =>
  form.value.totalUnits > 0
    ? pct(form.value.cancelledUnits / form.value.totalUnits)
    : '—'
);
const previewValidRate = computed(() =>
  form.value.totalUnits > 0
    ? pct(form.value.shippedUnits / form.value.totalUnits)
    : '—'
);

// 月度合计（表尾）：台数加权算平均取消率/有效率。
const monthTotals = computed(() => {
  const n = v => Number(v || 0);
  const t = records.value.reduce(
    (a, r) => ({
      orders: a.orders + n(r.totalOrders),
      units: a.units + n(r.totalUnits),
      amountCny: a.amountCny + n(r.salesAmountCny),
      cancelled: a.cancelled + n(r.cancelledUnits),
      shipped: a.shipped + n(r.shippedUnits),
      influencer: a.influencer + n(r.influencerUnits),
    }),
    {
      orders: 0,
      units: 0,
      amountCny: 0,
      cancelled: 0,
      shipped: 0,
      influencer: 0,
    }
  );
  t.cancelRate = t.units ? t.cancelled / t.units : null;
  t.validRate = t.units ? t.shipped / t.units : null;
  return t;
});

// 同一天的记录合并成一组（一张卡）：卡头日期 + 当日合计，卡内各店铺一行。
const WEEK = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const weekday = date => {
  const dt = new Date(`${date}T00:00:00`);
  return Number.isNaN(dt.getTime()) ? '' : WEEK[dt.getDay()];
};
const groupedByDate = computed(() => {
  const n = v => Number(v || 0);
  const map = new Map();
  records.value.forEach(r => {
    if (!map.has(r.saleDate)) map.set(r.saleDate, []);
    map.get(r.saleDate).push(r);
  });
  return [...map.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([date, rows]) => ({
      date,
      rows,
      orders: rows.reduce((s, r) => s + n(r.totalOrders), 0),
      units: rows.reduce((s, r) => s + n(r.totalUnits), 0),
      amountCny: rows.reduce((s, r) => s + n(r.salesAmountCny), 0),
    }));
});

const loadRecords = async () => {
  loading.value = true;
  try {
    records.value = await recordsStore.get({
      month: filters.value.month,
      shop_id: filters.value.shopId,
    });
  } catch (e) {
    useAlert(e?.message || '加载失败');
  } finally {
    loading.value = false;
  }
};

const openNew = () => {
  if (!activeShops.value.length) {
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

const openEdit = record => {
  form.value = {
    id: record.id,
    saleDate: record.saleDate,
    shopId: record.shopId,
    allianceLiveOrders: record.allianceLiveOrders || 0,
    allianceOrders: record.allianceOrders || 0,
    productCardOrders: record.productCardOrders || 0,
    merchantOrders: record.merchantOrders || 0,
    totalOrders: record.totalOrders,
    totalUnits: record.totalUnits,
    salesAmount: Number(record.salesAmount),
    currency: record.currency,
    cancelledUnits: record.cancelledUnits,
    shippedUnits: record.shippedUnits,
    influencerUnits: record.influencerUnits,
    remark: record.remark || '',
  };
  showForm.value = true;
};

const submit = async () => {
  if (!form.value.shopId) return useAlert('请选择店铺');
  if (!form.value.saleDate) return useAlert('请选择日期');
  // 总订单以订单来源四项之和为准（后端亦会兜底求和）。
  const payload = { ...form.value, totalOrders: orderSourceTotal.value };
  try {
    if (isEdit.value) {
      await recordsStore.update(payload);
    } else {
      delete payload.id;
      await recordsStore.create(payload);
    }
    showForm.value = false;
    await loadRecords();
    return useAlert('已保存');
  } catch (e) {
    return useAlert(e?.message || '保存失败（同店同日只能一条）');
  }
};

const remove = async record => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `删除 ${record.saleDate} · ${shopName(record.shopId)} 的记录？`
    )
  ) {
    return;
  }
  try {
    await recordsStore.delete(record.id);
    await loadRecords();
    useAlert('已删除');
  } catch (e) {
    useAlert(e?.message || '删除失败');
  }
};

onMounted(async () => {
  try {
    shops.value = await shopsStore.get();
  } catch (e) {
    /* 店铺取不到不阻塞列表 */
  }
  await loadRecords();
});

// 进度条填充宽度：把 0..1 的比率钳位到 0–100% 的字符串（仅用于动态条宽内联 style）。
const barWidth = rate => {
  const p = Math.min(100, Math.max(0, Number(rate || 0) * 100));
  return `${p}%`;
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full max-w-5xl px-4 py-4 mx-auto sm:px-8 sm:py-6">
      <!-- 头部：标题 + 筛选 + 新增 -->
      <div class="flex flex-wrap items-center justify-between gap-3 mb-5 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">每日录入</h1>
          <p class="mt-0.5 text-sm text-n-slate-11">
            每天每店录一张卡；取消率、有效率、RMB 金额自动计算。
          </p>
        </div>
        <div class="flex flex-wrap items-center w-full gap-2 sm:w-auto">
          <MonthPicker
            v-model="filters.month"
            trigger-class="w-40 h-10"
            :clearable="false"
            @change="loadRecords"
          />
          <SelectCard
            v-model="filters.shopId"
            :options="shopFilterOptions"
            trigger-class="w-40 h-10"
            @update:model-value="loadRecords"
          />
          <Button
            color="iris"
            icon="i-lucide-plus"
            label="新增记录"
            class="shrink-0"
            @click="openNew"
          />
        </div>
      </div>

      <!-- 本月合计汇总条 -->
      <div
        v-if="!loading && records.length"
        class="flex flex-wrap items-center gap-x-6 gap-y-3 px-4 py-3 mb-5 rounded-2xl border border-n-weak bg-gradient-to-r from-n-alpha-1 to-n-alpha-2 sm:gap-x-8 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8"
      >
        <div class="flex flex-col">
          <span class="text-[11px] text-n-slate-11">本月合计</span>
          <span class="text-sm font-semibold text-n-slate-12">
            {{ filters.month }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-[11px] font-medium text-n-iris-11">总订单</span>
          <span class="text-2xl font-bold tabular-nums text-n-iris-11">
            {{ monthTotals.orders }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-[11px] text-n-slate-11">总台数</span>
          <span class="text-lg font-bold tabular-nums text-n-slate-12">
            {{ monthTotals.units }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-[11px] text-n-slate-11">总销售额 RMB</span>
          <span class="text-lg font-bold tabular-nums text-n-slate-12">
            {{ cny(monthTotals.amountCny) }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-[11px] text-n-slate-11">平均取消率</span>
          <span
            class="text-lg font-bold tabular-nums"
            :class="
              monthTotals.cancelRate > 0.3
                ? 'text-n-ruby-11'
                : 'text-n-slate-12'
            "
          >
            {{ pct(monthTotals.cancelRate) }}
          </span>
        </div>
        <div class="flex flex-col">
          <span class="text-[11px] text-n-slate-11">平均有效率</span>
          <span class="text-lg font-bold tabular-nums text-n-iris-11">
            {{ pct(monthTotals.validRate) }}
          </span>
        </div>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <!-- 空状态卡 -->
      <div
        v-else-if="!records.length"
        class="flex flex-col items-center justify-center gap-2 px-4 py-16 text-center rounded-xl border border-dashed border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
      >
        <span
          class="i-lucide-clipboard-list text-2xl text-n-slate-9"
          aria-hidden="true"
        />
        <p class="text-sm text-n-slate-11">
          本月暂无记录，点右上角「新增记录」开始录入。
        </p>
      </div>

      <!-- 按日期分组：同一天合并一张卡，卡内各店铺一行 -->
      <div v-else class="flex flex-col gap-3">
        <div
          v-for="g in groupedByDate"
          :key="g.date"
          class="overflow-hidden border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
        >
          <!-- 卡头：日期 + 当日合计 -->
          <div
            class="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5 border-b border-n-weak bg-n-alpha-1"
          >
            <div class="flex items-baseline gap-2">
              <span class="text-sm font-bold tabular-nums text-n-slate-12">
                {{ g.date }}
              </span>
              <span class="text-xs text-n-slate-10">{{ weekday(g.date) }}</span>
            </div>
            <div class="flex items-center gap-4 text-xs">
              <div class="flex items-center gap-1">
                <span class="text-n-slate-11">当日订单</span>
                <b class="tabular-nums text-n-iris-11">{{ g.orders }}</b>
              </div>
              <div class="flex items-center gap-1">
                <span class="text-n-slate-11">台数</span>
                <b class="tabular-nums text-n-slate-12">{{ g.units }}</b>
              </div>
              <div class="flex items-center gap-1">
                <span class="text-n-slate-11">销售额</span>
                <b class="tabular-nums text-n-slate-12">
                  {{ cny(g.amountCny) }}
                </b>
              </div>
            </div>
          </div>

          <!-- 各店铺一行 -->
          <div
            v-for="r in g.rows"
            :key="r.id"
            class="flex flex-wrap items-center gap-4 px-4 py-3 border-b last:border-b-0 border-n-weak transition hover:bg-n-alpha-1"
          >
            <!-- 店铺 -->
            <span
              class="w-28 shrink-0 inline-flex px-2 py-0.5 rounded-md text-xs text-n-slate-12 bg-n-alpha-2"
            >
              {{ r.shopName || shopName(r.shopId) }}
            </span>

            <!-- 指标块（订单为核心，紫色高亮） -->
            <div class="flex flex-wrap items-center gap-x-5 gap-y-2">
              <div class="flex flex-col px-3 py-1.5 rounded-lg bg-n-iris-3">
                <span class="text-[11px] font-medium text-n-iris-11">订单</span>
                <span
                  class="text-2xl font-bold leading-none tabular-nums text-n-iris-11"
                >
                  {{ r.totalOrders }}
                </span>
              </div>
              <div class="flex flex-col">
                <span class="text-[11px] text-n-slate-11">总台数</span>
                <span
                  class="text-sm font-semibold tabular-nums text-n-slate-12"
                >
                  {{ r.totalUnits }}
                </span>
              </div>
              <div class="flex flex-col">
                <span class="text-[11px] text-n-slate-11">实发</span>
                <span
                  class="text-sm font-semibold tabular-nums text-n-slate-12"
                >
                  {{ r.shippedUnits }}
                </span>
              </div>
              <div class="flex flex-col">
                <span class="text-[11px] text-n-slate-11">达人</span>
                <span
                  class="text-sm font-semibold tabular-nums"
                  :class="
                    r.influencerUnits ? 'text-n-slate-12' : 'text-n-slate-9'
                  "
                >
                  {{ r.influencerUnits }}
                </span>
              </div>
            </div>

            <!-- 进度条：取消率 / 有效率 -->
            <div class="flex flex-col gap-2 min-w-[10rem] flex-1">
              <div class="flex items-center gap-2">
                <span class="text-[11px] w-12 shrink-0 text-n-slate-11">
                  取消率
                </span>
                <div class="flex-1 h-1.5 rounded-full bg-n-alpha-3">
                  <div
                    class="h-1.5 rounded-full"
                    :class="r.cancelRate > 0.3 ? 'bg-n-ruby-9' : 'bg-n-slate-8'"
                    :style="{ width: barWidth(r.cancelRate) }"
                  />
                </div>
                <span
                  class="text-[11px] w-12 text-right tabular-nums shrink-0"
                  :class="
                    r.cancelRate > 0.3
                      ? 'text-n-ruby-11 font-semibold'
                      : 'text-n-slate-11'
                  "
                >
                  {{ pct(r.cancelRate) }}
                </span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-[11px] w-12 shrink-0 text-n-slate-11">
                  有效率
                </span>
                <div class="flex-1 h-1.5 rounded-full bg-n-alpha-3">
                  <div
                    class="h-1.5 rounded-full bg-n-iris-9"
                    :style="{ width: barWidth(r.validRate) }"
                  />
                </div>
                <span
                  class="text-[11px] w-12 text-right tabular-nums shrink-0 text-n-iris-11"
                >
                  {{ pct(r.validRate) }}
                </span>
              </div>
            </div>

            <!-- 销售额 -->
            <div class="flex flex-col items-end min-w-[6rem]">
              <span class="text-base font-bold tabular-nums text-n-slate-12">
                {{ cny(r.salesAmountCny) }}
              </span>
              <span class="text-[11px] tabular-nums text-n-slate-10">
                {{ Number(r.salesAmount).toLocaleString() }} {{ r.currency }}
              </span>
            </div>

            <!-- 操作 -->
            <div class="flex items-center gap-0.5 shrink-0">
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
          </div>
        </div>
      </div>
    </div>

    <!-- 录入/编辑弹窗 -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showForm = false"
    >
      <div
        class="w-full max-w-[95vw] sm:max-w-lg p-4 sm:p-6 overflow-y-auto max-h-[90vh] rounded-2xl bg-n-solid-1 shadow-xl [.theme-classic_&]:sm:!p-8"
      >
        <h2 class="mb-4 text-lg font-semibold text-n-slate-12">
          {{ isEdit ? '编辑记录' : '新增记录' }}
        </h2>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">日期</span>
            <input
              v-model="form.saleDate"
              type="date"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">店铺</span>
            <select
              v-model="form.shopId"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option v-for="s in activeShops" :key="s.id" :value="s.id">
                {{ s.name }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">联盟直播订单</span>
            <input
              v-model.number="form.allianceLiveOrders"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">联盟订单</span>
            <input
              v-model.number="form.allianceOrders"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">商品卡订单</span>
            <input
              v-model.number="form.productCardOrders"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">商家订单</span>
            <input
              v-model.number="form.merchantOrders"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">总订单（自动合计）</span>
            <input
              :value="orderSourceTotal"
              type="number"
              readonly
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-alpha-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">总台数</span>
            <input
              v-model.number="form.totalUnits"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">总销售额</span>
            <input
              v-model.number="form.salesAmount"
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
            <span class="text-xs text-n-slate-11">当天取消台数</span>
            <input
              v-model.number="form.cancelledUnits"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">实发台数</span>
            <input
              v-model.number="form.shippedUnits"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">达人销售台数</span>
            <input
              v-model.number="form.influencerUnits"
              type="number"
              min="0"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col col-span-1 gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">备注（选填）</span>
            <input
              v-model="form.remark"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </div>

        <!-- 自动计算预览 -->
        <div
          class="flex flex-wrap gap-x-4 gap-y-1 px-3 py-2 mt-4 text-xs rounded-lg text-n-slate-11 bg-n-alpha-1"
        >
          <span
            >取消率 <b class="text-n-slate-12">{{ previewCancelRate }}</b></span
          >
          <span
            >订单有效率
            <b class="text-n-slate-12">{{ previewValidRate }}</b></span
          >
          <span class="text-n-slate-10">RMB 金额按实时汇率于保存时计算</span>
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
