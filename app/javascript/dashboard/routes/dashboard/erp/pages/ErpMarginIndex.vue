<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpOrderCostAPI from 'dashboard/api/erp/orderCosts';
import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';

// 成本与毛利：订单成本归集（材料/加工/运费/佣金/其他）+ 毛利报表（订单 / 业务员 / 客户维度）。
// ⚠️ 权限墙核心区：这些数只在 ERP 内可见，销售端接口一律不输出。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('cost'));

const TABS = [
  { key: 'margin', label: '毛利报表' },
  { key: 'costs', label: '成本归集' },
];
const COST_TYPES = [
  { value: 'MATERIAL', label: '材料成本' },
  { value: 'PROCESS', label: '加工/外协' },
  { value: 'FREIGHT', label: '运费' },
  { value: 'COMMISSION', label: '佣金' },
  { value: 'OTHER', label: '其他' },
];
const GROUPS = [
  { value: '', label: '不汇总' },
  { value: 'owner', label: '按业务员' },
  { value: 'customer', label: '按客户' },
];

const money = micros => (micros ? fmtMoney(micros) : '—');
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);

const activeTab = ref('margin');
const loading = ref(false);
const groupBy = ref('owner');
const marginRows = ref([]);
const marginSummary = ref([]);
const marginMeta = ref({});
const costs = ref([]);

const loadMargin = async () => {
  loading.value = true;
  try {
    const { data } = await ErpOrderCostAPI.margin({ group_by: groupBy.value });
    marginRows.value = data.payload;
    marginSummary.value = data.summary;
    marginMeta.value = data.meta;
  } finally {
    loading.value = false;
  }
};
const loadCosts = async () => {
  loading.value = true;
  try {
    const { data } = await ErpOrderCostAPI.get();
    costs.value = data.payload;
  } finally {
    loading.value = false;
  }
};
// 一键把 MES 的领料/外协采购算成成本行。日常出货时已自动触发，这里是补历史/兜底。
// 幂等，重复点不会翻倍；手工补录的行不受影响。
const rollingUp = ref(false);
const rollupFromMes = async () => {
  rollingUp.value = true;
  try {
    const { data } = await ErpOrderCostAPI.rollup({});
    const { synced = 0, scanned = 0 } = data.payload || {};
    useAlert(`已归集 ${synced} 条成本（扫描生产订单 ${scanned} 张）`);
    await loadCosts();
  } catch (error) {
    useAlert(error?.response?.data?.error || '归集失败');
  } finally {
    rollingUp.value = false;
  }
};

// 导出 Excel。
// ⚠️ 明细在页面上只给 200 行，导出**必须重新向后端要全量**——导出一张只有 200 行、
// 却不说自己缺了的毛利表，比不给导出更坏（拿去汇报就是错数）。
// 后端封顶 5000 行，真超了也会带 truncated 标记，这里如实弹出来。
const exporting = ref(false);
const exportExcel = async () => {
  exporting.value = true;
  try {
    const { data } = await ErpOrderCostAPI.margin({
      group_by: groupBy.value,
      limit: 5000,
    });
    const meta = data.meta || {};
    exportRowsToExcel(
      {
        title: '毛利报表（订单维度）',
        meta: [
          { label: '导出时间', value: new Date().toLocaleString() },
          { label: '订单数', value: meta.total_count ?? data.payload.length },
          { label: '收入合计', value: (meta.revenue_micros || 0) / 1_000_000 },
          { label: '成本合计', value: (meta.cost_micros || 0) / 1_000_000 },
          { label: '毛利合计', value: (meta.margin_micros || 0) / 1_000_000 },
          {
            label: '口径',
            value:
              '收入优先取应收台账金额，没建台账的退回销售订单金额；成本＝归集行合计',
          },
        ],
        columns: [
          { label: '订单号', key: 'order_no' },
          { label: '订单名称', key: 'order_name' },
          { label: '下单日期', key: 'order_date' },
          { label: '客户', key: 'customer_name' },
          { label: '业务员', key: 'owner_name' },
          { label: '收入', key: 'revenue_micros', money: true },
          { label: '归集成本', key: 'cost_micros', money: true },
          { label: '毛利', key: 'margin_micros', money: true },
          { label: '毛利率(%)', key: 'margin_rate' },
          { label: '应收单号', key: 'receivable_no' },
        ],
        rows: data.payload,
      },
      `毛利报表_${today()}`
    );
    if (meta.truncated) {
      useAlert(
        `共 ${meta.total_count} 单，本次只导出了前 ${data.payload.length} 单，请缩小日期范围再导一次`
      );
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || '导出失败');
  } finally {
    exporting.value = false;
  }
};

const switchTab = key => {
  activeTab.value = key;
  return key === 'margin' ? loadMargin() : loadCosts();
};

/* 成本录入 */
const dialogRef = ref(null);
const orderOptions = ref([]);
const form = reactive({
  crmSalesOrderId: '',
  costType: 'MATERIAL',
  amount: '',
  happenedAt: today(),
  remark: '',
});
const searchOrders = async q => {
  const { data } = await CrmSalesOrderAPI.get({ q, page: 1 });
  orderOptions.value = (data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no} ${o.name || ''}`.trim(),
  }));
};
const openCost = () => {
  Object.assign(form, {
    crmSalesOrderId: '',
    costType: 'MATERIAL',
    amount: '',
    happenedAt: today(),
    remark: '',
  });
  searchOrders('');
  dialogRef.value?.open();
};
const submitCost = async () => {
  if (!form.crmSalesOrderId || !form.amount) return;
  try {
    await ErpOrderCostAPI.create({
      order_cost: {
        crm_sales_order_id: form.crmSalesOrderId,
        cost_type: form.costType,
        amount_micros: toMicros(form.amount),
        happened_at: form.happenedAt,
        remark: form.remark,
      },
    });
    useAlert('成本已归集');
    dialogRef.value?.close();
    loadCosts();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};
const removeCost = async row => {
  await ErpOrderCostAPI.delete(row.id);
  useAlert('已删除');
  loadCosts();
};

onMounted(loadMargin);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-percent size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">成本与毛利</h1>
        <span v-if="activeTab === 'margin'" class="text-sm text-n-slate-11">
          收入 {{ money(marginMeta.revenue_micros) }} · 成本
          {{ money(marginMeta.cost_micros) }} · 毛利
          <span class="text-n-slate-12">{{
            money(marginMeta.margin_micros)
          }}</span>
          <!-- 合计是全量口径；明细只展示前 200 行，截断时提示收窄日期范围 -->
          <span v-if="marginMeta.truncated" class="text-n-amber-11">
            · 共 {{ marginMeta.total_count }} 单，明细仅展示前 200
            行（合计为全量），可缩小日期范围查看
          </span>
        </span>
      </div>
      <div class="flex items-center gap-2">
        <!-- 导出是只读动作，毛利页签就给；归集与补录才要写权限 -->
        <Button
          v-if="activeTab === 'margin'"
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :is-loading="exporting"
          :disabled="!marginRows.length"
          @click="exportExcel"
        />
        <template v-if="canWrite && activeTab === 'costs'">
          <Button
            label="从 MES 归集"
            color="slate"
            variant="faded"
            size="sm"
            :is-loading="rollingUp"
            @click="rollupFromMes"
          />
          <Button label="手工补录" color="iris" size="sm" @click="openCost" />
        </template>
      </div>
    </div>

    <div class="flex items-center gap-2 px-6 pb-3">
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="h-9 px-3 text-sm transition-colors rounded-lg"
        :class="
          activeTab === tab.key
            ? 'bg-n-iris-9 text-white'
            : 'text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="switchTab(tab.key)"
      >
        {{ tab.label }}
      </button>
      <SelectCard
        v-if="activeTab === 'margin'"
        v-model="groupBy"
        :options="GROUPS"
        @update:model-value="loadMargin"
      />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>

      <template v-else-if="activeTab === 'margin'">
        <table
          v-if="marginSummary.length"
          class="w-full max-w-3xl mb-6 text-sm"
        >
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-3 font-medium">
                {{ groupBy === 'customer' ? '客户' : '业务员' }}
              </th>
              <th class="px-3 py-3 font-medium text-right">订单数</th>
              <th class="px-3 py-3 font-medium text-right">收入</th>
              <th class="px-3 py-3 font-medium text-right">成本</th>
              <th class="px-3 py-3 font-medium text-right">毛利</th>
              <th class="px-3 py-3 font-medium text-right">毛利率</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in marginSummary"
              :key="row.name"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-2 text-n-slate-12">{{ row.name }}</td>
              <td class="px-3 py-2 text-right text-n-slate-11">
                {{ row.order_count }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.revenue_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(row.cost_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.margin_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ row.margin_rate == null ? '—' : `${row.margin_rate}%` }}
              </td>
            </tr>
          </tbody>
        </table>

        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-3 font-medium">订单</th>
              <th class="px-3 py-3 font-medium">客户 / 业务员</th>
              <th class="px-3 py-3 font-medium text-right">收入</th>
              <th class="px-3 py-3 font-medium text-right">归集成本</th>
              <th class="px-3 py-3 font-medium text-right">毛利</th>
              <th class="px-3 py-3 font-medium text-right">毛利率</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in marginRows"
              :key="row.order_id"
              class="border-b border-n-weak"
            >
              <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
                {{ row.order_no }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ row.customer_name }}
                <span v-if="row.owner_name">· {{ row.owner_name }}</span>
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.revenue_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ money(row.cost_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-12">
                {{ money(row.margin_micros) }}
              </td>
              <td class="px-3 py-2 font-mono text-right text-n-slate-11">
                {{ row.margin_rate == null ? '—' : `${row.margin_rate}%` }}
              </td>
            </tr>
          </tbody>
        </table>
        <p class="mt-3 text-xs text-n-slate-10">
          收入优先取应收台账金额（财务确认过的），没建台账的退回销售订单金额；成本＝归集行合计。
          没归集成本的订单毛利率显示 100%，只说明成本还没录。
        </p>
      </template>

      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">订单</th>
            <th class="px-3 py-3 font-medium">成本类型</th>
            <th class="px-3 py-3 font-medium text-right">金额</th>
            <th class="px-3 py-3 font-medium">发生日</th>
            <th class="px-3 py-3 font-medium">备注</th>
            <th class="px-3 py-3 font-medium">录入</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in costs" :key="row.id" class="border-b border-n-weak">
            <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
              {{ row.order_no }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.cost_type_label }}</td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.base_amount_micros) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ row.happened_at || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.remark || '—' }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ row.created_by_name || '—' }}
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end">
                <Button
                  v-if="canWrite"
                  label="删除"
                  color="ruby"
                  variant="ghost"
                  size="xs"
                  @click="removeCost(row)"
                />
              </div>
            </td>
          </tr>
          <tr v-if="!costs.length">
            <td colspan="7" class="px-3 py-10 text-center text-n-slate-11">
              还没有归集成本。点右上角「归集成本」把材料/加工/运费挂到订单上。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="2xl"
      confirm-button-color="iris"
      title="归集订单成本"
      :disable-confirm-button="!form.crmSalesOrderId || !form.amount"
      @confirm="submitCost"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            销售订单 <span class="text-n-ruby-11">*</span>
          </label>
          <ComboBox
            v-model="form.crmSalesOrderId"
            :options="orderOptions"
            use-api-results
            placeholder="搜订单号"
            @search="searchOrders"
          />
        </div>
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">成本类型</label>
            <SelectCard v-model="form.costType" :options="COST_TYPES" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              金额 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="form.amount"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">发生日期</label>
            <DatePicker v-model="form.happenedAt" :clearable="false" block />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" size="sm" custom-input-class="!h-9" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
