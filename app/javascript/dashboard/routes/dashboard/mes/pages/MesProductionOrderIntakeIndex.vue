<script setup>
import { ref, reactive, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMesProductionOrdersStore } from 'dashboard/stores/mes/productionOrders';
import { getActiveProductLine } from 'dashboard/composables/useMesProductLine';
import {
  SPEC_TEMPLATES,
  blankSpec,
} from 'dashboard/routes/dashboard/mes/pages/orderSpecFields';
import MesOrderSpecForm from 'dashboard/components-next/mes/MesOrderSpecForm.vue';

const router = useRouter();
const { accountScopedRoute } = useAccount();
const store = useMesProductionOrdersStore();

const TEMPLATES = Object.entries(SPEC_TEMPLATES); // [[value, {label,fields}], ...]
const defaultTemplate = () => {
  const line = getActiveProductLine();
  return SPEC_TEMPLATES[line] ? line : 'TABLET';
};

const template = ref(defaultTemplate());
const base = reactive({
  productName: '',
  qty: '',
  unit: '台',
  deliveryDate: '',
});
const spec = ref(blankSpec(template.value));

const setTemplate = t => {
  template.value = t;
  spec.value = blankSpec(t); // 换模板重置规格
};

const submitting = ref(false);
const result = ref(null);

const missing = computed(() => {
  const m = [];
  if (!base.productName.trim()) m.push('成品名称');
  if (!Number(base.qty)) m.push('数量');
  return m;
});
const canSubmit = computed(
  () => missing.value.length === 0 && !submitting.value
);

const reset = () => {
  Object.assign(base, {
    productName: '',
    qty: '',
    unit: '台',
    deliveryDate: '',
  });
  spec.value = blankSpec(template.value);
};

const submit = async () => {
  if (!canSubmit.value) return;
  submitting.value = true;
  result.value = null;
  try {
    const ok = await store.create({
      productName: base.productName.trim(),
      qty: Number(base.qty),
      unit: base.unit,
      deliveryDate: base.deliveryDate || undefined,
      productLine: template.value,
      spec: spec.value,
    });
    if (ok) result.value = { ok: true, orderNo: ok.orderNo };
    else result.value = { ok: false, msg: '建单失败' };
    if (ok) reset();
  } catch (e) {
    result.value = { ok: false, msg: e?.response?.data?.error || '建单失败' };
  } finally {
    submitting.value = false;
  }
};

const backToList = () =>
  router.push(accountScopedRoute('mes_production_orders_index'));
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">新建生产订单</h1>
      <button
        class="text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="backToList"
      >
        ← 返回生产订单
      </button>
    </div>

    <div class="flex flex-col w-full max-w-3xl gap-4 px-6 py-5">
      <p class="text-xs text-n-slate-11">
        定制生产订单建单。先选产品线，按对应模板填规格；带
        <span class="text-n-ruby-11">*</span>
        为必填。建单后进入「销售订单确定」阶段，可挂 BOM、下发采购。
      </p>

      <!-- 基本信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        基本信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">
            产品线 / 模板 <span class="text-n-ruby-11">*</span>
          </span>
          <select
            :value="template"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            @change="e => setTemplate(e.target.value)"
          >
            <option v-for="[val, t] in TEMPLATES" :key="val" :value="val">
              {{ t.label }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">
            成品名称 <span class="text-n-ruby-11">*</span>
          </span>
          <input
            v-model="base.productName"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如：商显一体机 43寸 / Winny K11"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            数量 <span class="text-n-ruby-11">*</span>
          </span>
          <input
            v-model="base.qty"
            type="number"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="400"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">单位</span>
          <input
            v-model="base.unit"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="台 / 片 / pcs"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">期望交期</span>
          <input
            v-model="base.deliveryDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
      </div>

      <!-- 定制规格 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        定制规格 · {{ (SPEC_TEMPLATES[template] || {}).label }}
      </div>
      <MesOrderSpecForm v-model:spec="spec" :template="template" />

      <div class="flex items-center gap-3 mt-1">
        <button
          class="h-10 px-6 text-sm font-medium text-white transition-colors rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!canSubmit"
          @click="submit"
        >
          {{ submitting ? '建单中…' : '建单' }}
        </button>
        <span v-if="missing.length" class="text-xs text-n-slate-11">
          请填写：{{ missing.join('、') }}
        </span>
      </div>

      <div
        v-if="result?.ok"
        class="flex items-center gap-3 p-3 text-sm border rounded-lg border-n-teal-8 text-n-teal-11"
      >
        <span>✅ 已建单 {{ result.orderNo }}，可继续建下一单。</span>
        <button class="underline text-n-iris-11" @click="backToList">
          去生产订单查看
        </button>
      </div>
      <div
        v-else-if="result && !result.ok"
        class="p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        ❌ {{ result.msg }}
      </div>
    </div>
  </div>
</template>
