<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import ErpSettingAPI from 'dashboard/api/erp/settings';
import ErpLedgerAccountAPI from 'dashboard/api/erp/ledgerAccounts';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

// 财务设置：账套级会计政策 + 存货科目映射。
// 这几项原先只能改数据库——财务改个税率要排开发，等于「自己能改」没做到。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('ledger'));

const TABS = [
  { key: 'policy', label: '会计政策' },
  { key: 'inventory', label: '存货科目映射' },
];
const activeTab = ref('policy');

const loading = ref(false);
const saving = ref(false);

/* ---------------- 会计政策 ---------------- */
const policy = reactive({
  companyName: '',
  fiscalStartDate: '',
  defaultOutputTaxRate: 13,
  amountIncludesTax: true,
  receivablesEnabled: false,
});
const policyMeta = ref({});

const BOOL_OPTIONS = [
  { value: 'true', label: '默认含税' },
  { value: 'false', label: '默认不含税' },
];
const SWITCH_OPTIONS = [
  { value: 'true', label: '已启用' },
  { value: 'false', label: '未启用' },
];
// SelectCard 的值走字符串，布尔字段在这里转一手。
const includesTaxValue = computed({
  get: () => String(policy.amountIncludesTax),
  set: v => {
    policy.amountIncludesTax = v === 'true';
  },
});
const receivablesValue = computed({
  get: () => String(policy.receivablesEnabled),
  set: v => {
    policy.receivablesEnabled = v === 'true';
  },
});

const loadPolicy = async () => {
  loading.value = true;
  try {
    const { data } = await ErpSettingAPI.get();
    policy.companyName = data.payload.company_name || '';
    policy.fiscalStartDate = data.payload.fiscal_start_date || '';
    policy.defaultOutputTaxRate = data.payload.default_output_tax_rate;
    policy.amountIncludesTax = data.payload.amount_includes_tax;
    policy.receivablesEnabled = data.payload.receivables_enabled;
    policyMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const savePolicy = async () => {
  saving.value = true;
  try {
    const { data } = await ErpSettingAPI.save({
      company_name: policy.companyName.trim() || null,
      fiscal_start_date: policy.fiscalStartDate || null,
      default_output_tax_rate: policy.defaultOutputTaxRate,
      amount_includes_tax: policy.amountIncludesTax,
      receivables_enabled: policy.receivablesEnabled,
    });
    policyMeta.value = data.meta;
    useAlert('会计政策已保存');
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    saving.value = false;
  }
};

/* ---------------- 存货科目映射 ---------------- */
// 产品档案的「来源类别」→ 采购入库凭证的借方存货科目。
// 类别有两百多个（「成品」一项就有二十几种写法），所以是映射表而不是枚举。
const invRows = ref([]);
const invMeta = ref({});
const invQuery = ref('');
const onlyConfigured = ref(false);

const loadInventory = async () => {
  loading.value = true;
  try {
    const { data } = await ErpLedgerAccountAPI.inventoryMap();
    invRows.value = data.payload;
    invMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

const filteredInvRows = computed(() => {
  const q = invQuery.value.trim();
  return invRows.value.filter(
    row =>
      (!q || row.category.includes(q)) &&
      (!onlyConfigured.value || row.configured)
  );
});

const invOptions = computed(() => invMeta.value.options || []);
const suggestedDiffCount = computed(
  () => invRows.value.filter(row => row.code !== row.suggested).length
);

// 一键采纳建议：按类别名里的「成品/外购机/裸机」「委托加工/委外」关键字落科目，
// 剩下的留原材料。两百多个类别手点一遍没人受得了，采纳后仍可逐条改。
const applySuggestions = () => {
  invRows.value.forEach(row => {
    row.code = row.suggested;
  });
};

const saveInventory = async () => {
  saving.value = true;
  try {
    const map = {};
    invRows.value.forEach(row => {
      map[row.category] = row.code;
    });
    const { data } = await ErpLedgerAccountAPI.updateInventoryMap(map);
    useAlert(`已保存，${data.payload.configured_count} 个类别配了非默认科目`);
    await loadInventory();
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    saving.value = false;
  }
};

const switchTab = key => {
  activeTab.value = key;
  if (key === 'inventory' && !invRows.value.length) loadInventory();
};

onMounted(loadPolicy);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-settings-2 size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">财务设置</h1>
      </div>
      <Button
        label="刷新"
        color="slate"
        size="sm"
        @click="activeTab === 'policy' ? loadPolicy() : loadInventory()"
      />
    </div>

    <div class="flex items-center gap-2 px-6 pb-3">
      <!-- 全站统一的页面级 Tab（灰槽 + 深色选中块），样式见 _next-colors.scss -->
      <div data-tabbar="page">
        <button
          v-for="tab in TABS"
          :key="tab.key"
          :aria-selected="activeTab === tab.key"
          @click="switchTab(tab.key)"
        >
          {{ tab.label }}
        </button>
      </div>
    </div>

    <!-- 会计政策 -->
    <div
      v-if="activeTab === 'policy'"
      class="flex-1 min-h-0 px-6 pb-6 overflow-auto"
    >
      <div class="max-w-2xl space-y-6">
        <div>
          <label class="block mb-1.5 text-label text-n-slate-12">
            编制单位
          </label>
          <Input v-model="policy.companyName" class="w-96" />
          <p class="mt-1.5 text-xs text-n-slate-10">
            财务报表（会企01/02/03）表头印的公司全称，填营业执照上的名字。
          </p>
        </div>

        <div>
          <label class="block mb-1.5 text-label text-n-slate-12">
            会计启用日
          </label>
          <DatePicker v-model="policy.fiscalStartDate" trigger-class="w-56" />
          <p class="mt-1.5 text-xs text-n-slate-10">
            账套切过来的那一天。这天之前的销售订单不进「待建账」——那些是上线时一次性迁进来的
            历史单，钱早收完了，建出来全是假应收；日切前的余额走「期末结账 →
            期初建账」一笔进总账。
            <span v-if="policyMeta.earliest_order_date">
              现有已确认订单 {{ policyMeta.total_orders }} 张，最早一张
              {{ policyMeta.earliest_order_date }}；按当前启用日有
              <span class="text-n-slate-12">
                {{ policyMeta.pending_after_cutoff }}
              </span>
              张在日切之后。
            </span>
          </p>
          <p
            v-if="!policy.fiscalStartDate"
            class="mt-1.5 text-xs text-n-amber-11"
          >
            尚未设置：待建账清单会列出全部 {{ policyMeta.total_orders }}
            张已确认订单（含历史单），批量建账前请先设好这一天。
          </p>
        </div>

        <div>
          <label class="block mb-1.5 text-label text-n-slate-12">
            默认销项税率（%）
          </label>
          <!-- 宽度一律由外层定宽盒子给：Input 的根元素占满父宽、SelectCard 的
               触发器恒 w-full，两者的宽度 prop 在宽容器里都压不住，套盒子才齐。 -->
          <div class="w-56">
            <Input
              v-model="policy.defaultOutputTaxRate"
              type="number"
              min="0"
              max="100"
            />
          </div>
          <p class="mt-1.5 text-xs text-n-slate-10">
            单据上没填税率时按币种推定：人民币单用这个税率，美金等外币出口单按
            0。 单据上填了税率的以单据为准。
          </p>
        </div>

        <div>
          <label class="block mb-1.5 text-label text-n-slate-12">
            订单金额含税口径（默认）
          </label>
          <div class="w-56">
            <SelectCard
              v-model="includesTaxValue"
              :options="BOOL_OPTIONS"
              block
            />
          </div>
          <p class="mt-1.5 text-xs text-n-slate-10">
            转单时可以逐单勾选，这里只是没勾过的单据跟随的默认值。含税 → 收入 =
            金额 ÷(1+税率)、应收 = 金额；不含税 → 收入 = 金额、应收 = 金额 +
            税额。
          </p>
        </div>

        <div>
          <label class="block mb-1.5 text-label text-n-slate-12">
            应收台账
          </label>
          <div class="w-56">
            <SelectCard
              v-model="receivablesValue"
              :options="SWITCH_OPTIONS"
              block
            />
          </div>
          <p class="mt-1.5 text-xs text-n-slate-10">
            未启用时销售订单「出货即完结」，不等应收收清；启用后订单要等应收收完才完结。
            账还在金蝶的过渡期保持未启用。
          </p>
        </div>

        <Button
          v-if="canWrite"
          label="保存会计政策"
          :is-loading="saving"
          @click="savePolicy"
        />
        <p v-else class="text-xs text-n-slate-10">
          只有财务与管理员可以改会计政策，出纳为只读。
        </p>
      </div>
    </div>

    <!-- 存货科目映射 -->
    <div v-else class="flex flex-col flex-1 min-h-0 px-6 pb-6">
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <Input
          v-model="invQuery"
          size="sm"
          placeholder="搜来源类别"
          custom-input-class="w-56"
        />
        <label
          class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
        >
          <input
            v-model="onlyConfigured"
            type="checkbox"
            class="accent-n-iris-9"
          />
          只看已配置
        </label>
        <span class="text-sm text-n-slate-11">
          共 {{ invRows.length }} 个类别，已配 {{ invMeta.configured_count }} 个
        </span>
        <div class="flex-1" />
        <Button
          v-if="canWrite && suggestedDiffCount > 0"
          :label="`采纳建议（${suggestedDiffCount} 项）`"
          color="slate"
          variant="faded"
          size="sm"
          @click="applySuggestions"
        />
        <Button
          v-if="canWrite"
          label="保存映射"
          size="sm"
          :is-loading="saving"
          @click="saveInventory"
        />
      </div>

      <div class="flex-1 min-h-0 overflow-auto">
        <table class="w-full max-w-3xl text-sm">
          <thead class="sticky top-0 bg-n-background">
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-3 font-medium">来源类别</th>
              <th class="px-3 py-3 font-medium text-right">产品数</th>
              <th class="px-3 py-3 font-medium">入库记入科目</th>
              <th class="px-3 py-3 font-medium">建议</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in filteredInvRows"
              :key="row.category"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-2 text-n-slate-12">{{ row.category }}</td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ row.product_count }}
              </td>
              <td class="px-3 py-2">
                <div class="w-48">
                  <SelectCard
                    v-model="row.code"
                    :options="invOptions"
                    :disabled="!canWrite"
                    block
                  />
                </div>
              </td>
              <td class="px-3 py-2 text-xs text-n-slate-10">
                <span v-if="row.code === row.suggested">—</span>
                <span v-else class="text-n-amber-11">
                  建议改为
                  {{
                    invOptions.find(o => o.value === row.suggested)?.label ||
                    row.suggested
                  }}
                </span>
              </td>
            </tr>
            <tr v-if="!filteredInvRows.length && !loading">
              <td colspan="4" class="px-3 py-10 text-center text-n-slate-11">
                {{
                  invRows.length
                    ? '没有匹配的来源类别，换个关键词试试。'
                    : '产品档案里还没有填过「来源类别」，填了之后这张表会自动列出来。'
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="mt-3 text-xs text-n-slate-10">
        采购入库凭证按这张表决定借方存货科目（贷方是应付账款）。没配过的类别一律落原材料——
        新类别不会把账做错，最多是记粗了，在这里补一条即可。
      </p>
    </div>
  </div>
</template>
