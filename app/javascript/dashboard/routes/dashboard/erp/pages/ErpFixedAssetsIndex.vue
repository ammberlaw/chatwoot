<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useErpRole } from 'dashboard/composables/useErpRole';
import { fmtMoney } from 'dashboard/helper/erpMoney';
import ErpFixedAssetAPI from 'dashboard/api/erp/fixedAssets';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import { exportRowsToExcel } from 'dashboard/helper/erpExcel';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

// 固定资产：直线法折旧（原值 ×(1-残值率) / 年限月数），按月一键计提，
// 全部在用资产汇总成一张待过账折旧凭证；处置/报废单独生成结转凭证。
const { erpCan } = useErpRole();
const canWrite = computed(() => erpCan('asset'));

const CATEGORIES = [
  { value: 'EQUIPMENT', label: '生产设备' },
  { value: 'VEHICLE', label: '车辆' },
  { value: 'ELECTRONIC', label: '电子设备' },
  { value: 'OFFICE', label: '办公家具' },
  { value: 'OTHER', label: '其他' },
];
const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'IN_USE', label: '在用' },
  { value: 'DISPOSED', label: '已处置' },
  { value: 'SCRAPPED', label: '已报废' },
];
const STATUS_CLASS = {
  IN_USE: 'bg-n-teal-3 text-n-teal-11',
  DISPOSED: 'bg-n-slate-3 text-n-slate-11',
  SCRAPPED: 'bg-n-slate-3 text-n-slate-11',
};

const money = micros => (micros ? fmtMoney(micros) : '—');
const toMicros = value => Math.round(Number(value || 0) * 1_000_000);
const today = () => new Date().toISOString().slice(0, 10);
const thisMonth = () => today().slice(0, 7);

const assets = ref([]);
const meta = ref({});
const loading = ref(false);
const statusFilter = ref('');
const keyword = ref('');
const period = ref(thisMonth());

const load = async () => {
  loading.value = true;
  try {
    const { data } = await ErpFixedAssetAPI.get({
      status: statusFilter.value,
      q: keyword.value.trim(),
    });
    assets.value = data.payload;
    meta.value = data.meta;
  } finally {
    loading.value = false;
  }
};

// 导出 Excel：导当前筛选出的全部资产（资产台账要盘点、要给审计，得能在 Excel 里接着算）。
const exportExcel = () =>
  exportRowsToExcel(
    {
      title: '固定资产台账',
      meta: [
        { label: '导出时间', value: new Date().toLocaleString() },
        {
          label: '筛选',
          value: `${statusFilter.value ? STATUS_OPTIONS.find(x => x.value === statusFilter.value)?.label : '全部状态'}${keyword.value.trim() ? `，关键字「${keyword.value.trim()}」` : ''}`,
        },
        { label: '资产台数', value: assets.value.length },
      ],
      columns: [
        { label: '资产编号', key: 'asset_no' },
        { label: '名称', key: 'name' },
        { label: '类别', key: 'category_label' },
        { label: '购入日', key: 'purchased_at' },
        { label: '原值', key: 'original_value_micros', money: true },
        { label: '使用月数', key: 'useful_months' },
        { label: '残值率', key: 'residual_rate' },
        { label: '月折旧', key: 'monthly_depreciation_micros', money: true },
        {
          label: '累计折旧',
          key: 'accumulated_depreciation_micros',
          money: true,
        },
        { label: '净值', key: 'net_value_micros', money: true },
        { label: '使用部门', key: 'department_name' },
        { label: '保管人', key: 'keeper_name' },
        { label: '状态', key: 'status_label' },
        { label: '处置日', key: 'disposed_at' },
        { label: '备注', key: 'remark' },
      ],
      rows: assets.value,
    },
    `固定资产台账_${today()}`
  );

const depreciate = async () => {
  try {
    const { data } = await ErpFixedAssetAPI.depreciate(period.value);
    useAlert(
      data.count
        ? `已计提 ${data.count} 台资产共 ${fmtMoney(data.amount_micros)}，凭证 ${data.voucher_no}（待过账）`
        : `${period.value} 没有需要计提的资产`
    );
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '计提失败');
  }
};

/* ---------------- 档案 ---------------- */
const dialogRef = ref(null);
const editing = ref(null);
const form = reactive({
  name: '',
  category: 'EQUIPMENT',
  purchasedAt: today(),
  originalValue: '',
  residualRate: 5,
  usefulMonths: 60,
  remark: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => form);
const monthlyPreview = computed(() => {
  const original = toMicros(form.originalValue);
  const months = Number(form.usefulMonths || 0);
  if (!original || !months) return 0;
  return Math.round(
    (original * (1 - Number(form.residualRate || 0) / 100)) / months
  );
});
const openAsset = (record = null) => {
  editing.value = record;
  Object.assign(form, {
    name: record?.name || '',
    category: record?.category || 'EQUIPMENT',
    purchasedAt: record?.purchased_at || today(),
    originalValue: record
      ? (record.original_value_micros / 1_000_000).toFixed(2)
      : '',
    residualRate: record ? Number(record.residual_rate) : 5,
    usefulMonths: record?.useful_months || 60,
    remark: record?.remark || '',
  });
  markPristine();
  dialogRef.value?.open();
};
const submitAsset = async () => {
  if (!form.name.trim() || !form.originalValue) return;
  const payload = {
    fixed_asset: {
      name: form.name.trim(),
      category: form.category,
      purchased_at: form.purchasedAt,
      original_value_micros: toMicros(form.originalValue),
      residual_rate: form.residualRate,
      useful_months: form.usefulMonths,
      remark: form.remark,
    },
  };
  try {
    if (editing.value) await ErpFixedAssetAPI.update(editing.value.id, payload);
    else await ErpFixedAssetAPI.create(payload);
    useAlert('资产档案已保存');
    dialogRef.value?.close();
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

/* ---------------- 处置 ---------------- */
const disposeRef = ref(null);
const disposing = ref(null);
const disposeForm = reactive({
  disposedAt: today(),
  income: '',
  scrapped: false,
});
const { isDirty: isDisposeDirty, markPristine: markDisposePristine } =
  useDirtyGuard(() => disposeForm);
const openDispose = record => {
  disposing.value = record;
  Object.assign(disposeForm, {
    disposedAt: today(),
    income: '',
    scrapped: false,
  });
  markDisposePristine();
  disposeRef.value?.open();
};
const submitDispose = async () => {
  try {
    await ErpFixedAssetAPI.dispose(disposing.value.id, {
      disposed_at: disposeForm.disposedAt,
      income_micros: toMicros(disposeForm.income),
      scrapped: disposeForm.scrapped,
    });
    useAlert(
      `${disposing.value.asset_no} 已${disposeForm.scrapped ? '报废' : '处置'}，已生成待过账结转凭证`
    );
    disposeRef.value?.close();
    load();
  } catch (error) {
    useAlert(error?.response?.data?.error || '处置失败');
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between gap-3 px-6 py-4">
      <div class="flex items-center gap-2">
        <div class="i-lucide-hard-drive size-5 text-n-iris-9" />
        <h1 class="text-xl font-semibold text-n-slate-12">固定资产</h1>
        <span class="text-sm text-n-slate-11">
          原值 {{ money(meta.original_micros) }} · 累计折旧
          {{ money(meta.accumulated_micros) }} · 净值
          <span class="text-n-slate-12">{{ money(meta.net_micros) }}</span>
        </span>
      </div>
      <div class="flex items-center gap-2">
        <Input
          v-model="keyword"
          size="sm"
          placeholder="搜编号 / 名称"
          custom-input-class="w-40"
          @keyup.enter="load"
        />
        <Button label="查询" color="slate" size="sm" @click="load" />
        <Button
          label="导出 Excel"
          color="slate"
          variant="faded"
          size="sm"
          :disabled="!assets.length"
          @click="exportExcel"
        />
        <Button
          v-if="canWrite"
          label="新增资产"
          color="iris"
          size="sm"
          @click="openAsset()"
        />
      </div>
    </div>

    <div class="flex items-center gap-2 px-6 pb-3">
      <SelectCard
        v-model="statusFilter"
        :options="STATUS_OPTIONS"
        @update:model-value="load"
      />
      <template v-if="canWrite">
        <span class="ml-2 text-sm text-n-slate-11">计提期间</span>
        <MonthPicker
          v-model="period"
          trigger-class="w-32 h-9"
          :clearable="false"
        />
        <Button
          label="一键计提折旧"
          color="slate"
          variant="faded"
          size="sm"
          @click="depreciate"
        />
        <span class="text-xs text-n-slate-10">
          汇总成一张待过账凭证，重复点不会翻倍
        </span>
      </template>
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="loading" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-3 font-medium">资产编号</th>
            <th class="px-3 py-3 font-medium">名称 / 类别</th>
            <th class="px-3 py-3 font-medium">购入日</th>
            <th class="px-3 py-3 font-medium text-right">原值</th>
            <th class="px-3 py-3 font-medium text-right">月折旧</th>
            <th class="px-3 py-3 font-medium text-right">累计折旧</th>
            <th class="px-3 py-3 font-medium text-right">净值</th>
            <th class="px-3 py-3 font-medium">状态</th>
            <th class="px-3 py-3 font-medium text-right">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in assets"
            :key="row.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-mono whitespace-nowrap text-n-slate-12">
              {{ row.asset_no }}
            </td>
            <td class="px-3 py-2 text-n-slate-12">
              {{ row.name }}
              <span class="text-xs text-n-slate-10">
                · {{ row.category_label }}
              </span>
            </td>
            <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
              {{ row.purchased_at }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.original_value_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.monthly_depreciation_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-11">
              {{ money(row.accumulated_depreciation_micros) }}
            </td>
            <td class="px-3 py-2 font-mono text-right text-n-slate-12">
              {{ money(row.net_value_micros) }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 text-xs rounded whitespace-nowrap"
                :class="STATUS_CLASS[row.status]"
              >
                {{ row.status_label }}
              </span>
            </td>
            <td class="px-3 py-2">
              <div class="flex items-center justify-end gap-1">
                <template v-if="canWrite && row.status === 'IN_USE'">
                  <Button
                    label="编辑"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    @click="openAsset(row)"
                  />
                  <Button
                    label="处置"
                    color="ruby"
                    variant="ghost"
                    size="xs"
                    @click="openDispose(row)"
                  />
                </template>
              </div>
            </td>
          </tr>
          <tr v-if="!assets.length">
            <td colspan="9" class="px-3 py-10 text-center text-n-slate-11">
              还没有固定资产。点右上角「新增资产」建档，之后每月一键计提折旧。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 档案 -->
    <Dialog
      ref="dialogRef"
      width="2xl"
      confirm-button-color="iris"
      :title="editing ? `编辑资产 ${editing.asset_no}` : '新增固定资产'"
      :disable-confirm-button="!form.name || !form.originalValue"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitAsset"
      @close="markPristine"
      @save="submitAsset"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              资产名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" size="sm" custom-input-class="!h-9" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">类别</label>
            <SelectCard v-model="form.category" :options="CATEGORIES" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">购入日期</label>
            <DatePicker v-model="form.purchasedAt" :clearable="false" block />
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              原值 <span class="text-n-ruby-11">*</span>
            </label>
            <Input
              v-model="form.originalValue"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">残值率(%)</label>
            <Input
              v-model="form.residualRate"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">折旧年限(月)</label>
            <Input
              v-model="form.usefulMonths"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
        </div>
        <div class="px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-11">
          直线法月折旧额 =
          <span class="font-mono text-n-slate-12">{{
            money(monthlyPreview)
          }}</span>
          （原值 ×（1 - 残值率）÷ 折旧月数）
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" size="sm" custom-input-class="!h-9" />
        </div>
      </div>
    </Dialog>

    <!-- 处置 -->
    <Dialog
      ref="disposeRef"
      width="lg"
      confirm-button-color="ruby"
      :title="`处置资产 ${disposing?.asset_no || ''}`"
      confirm-label="确认处置"
      :dirty="isDisposeDirty"
      dirty-save-label="保存"
      @confirm="submitDispose"
      @close="markDisposePristine"
      @save="submitDispose"
    >
      <div class="flex flex-col gap-4">
        <div class="text-sm text-n-slate-11">
          当前净值
          <span class="font-mono text-n-slate-12">
            {{ money(disposing?.net_value_micros) }}
          </span>
          ；处置收入与净值的差额会进「资产处置损益」，并生成待过账凭证。
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">处置日期</label>
            <DatePicker
              v-model="disposeForm.disposedAt"
              :clearable="false"
              block
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">处置收入</label>
            <Input
              v-model="disposeForm.income"
              size="sm"
              type="number"
              custom-input-class="!h-9"
            />
          </div>
        </div>
        <label class="flex items-center gap-2 text-heading-3 text-n-slate-12">
          <input
            v-model="disposeForm.scrapped"
            type="checkbox"
            class="w-4 h-4"
          />
          按报废处理（无处置收入）
        </label>
      </div>
    </Dialog>
  </div>
</template>
