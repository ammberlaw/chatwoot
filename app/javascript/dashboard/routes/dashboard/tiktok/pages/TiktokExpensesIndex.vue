<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import TiktokExpensesAPI from 'dashboard/api/tiktok/expenses';

import Button from 'dashboard/components-next/button/Button.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import AttachmentPreview from 'dashboard/components-next/attachment/AttachmentPreview.vue';

// TK 支出台账：店铺运营与部门日常开销，按部门收口（店铺选填）。
// 与 CRM 备用金台账互不重叠——TK 的支出在这里记，外币按落账时汇率折 RMB。
const CATEGORIES = [
  '广告花费',
  '物流费',
  '海外仓费用',
  '退货损耗',
  '达人合作',
  '平台费用',
  '人员费用',
  '办公用品',
  '设备采购',
  '其它',
];
const CURRENCIES = ['CNY', 'PHP', 'USD', 'EUR'];

// 附件在线预览（图片/PDF 直接看，其它给下载）。
const previewFile = ref(null);

const shopsStore = useTiktokShopsStore();
const deptStore = useTiktokDepartmentsStore();

const shops = ref([]);
const departments = ref([]);
const rows = ref([]);
const totalCny = ref(0);
const editableDeptIds = ref([]);
const loading = ref(false);

const thisMonth = () => new Date().toISOString().slice(0, 7);
const filters = ref({ month: thisMonth(), departmentId: '' });

const num = v => Number(v || 0);
const cny = v =>
  `¥${num(v).toLocaleString('zh-CN', { maximumFractionDigits: 2 })}`;

const canEditDept = id =>
  editableDeptIds.value === 'all' || editableDeptIds.value.includes(id);
const canCreate = computed(
  () => editableDeptIds.value === 'all' || editableDeptIds.value.length > 0
);

const departmentOptions = computed(() =>
  departments.value.map(d => ({ value: d.id, label: d.name }))
);
const departmentFilterOptions = computed(() => [
  { value: '', label: '全部部门' },
  ...departmentOptions.value,
]);

// 导出当前筛选的支出台账（.xlsx）。服务端生成，排版与出库利润表同一套：
// 按部门分组、每组小计、末尾总计。列比页面全（带原币/汇率/备注/录入人）。
const exporting = ref(false);
const exportXlsx = async () => {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const { data } = await TiktokExpensesAPI.export({
      month: filters.value.month,
      department_id: filters.value.departmentId,
    });
    const url = window.URL.createObjectURL(new Blob([data]));
    const a = document.createElement('a');
    a.href = url;
    const dept = departmentFilterOptions.value.find(
      o => o.value === filters.value.departmentId
    );
    a.download = `TikTok支出台账-${filters.value.month}${
      filters.value.departmentId ? `-${dept?.label || ''}` : ''
    }.xlsx`;
    a.click();
    window.URL.revokeObjectURL(url);
  } catch (e) {
    useAlert(e?.response?.data?.error || '导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};
// 按类别汇总，看钱花在哪块最多。
const byCategory = computed(() => {
  const map = new Map();
  rows.value.forEach(r => {
    map.set(r.category, (map.get(r.category) || 0) + num(r.amountCny));
  });
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
});

const load = async () => {
  loading.value = true;
  try {
    const { data } = await TiktokExpensesAPI.get({
      month: filters.value.month,
      department_id: filters.value.departmentId,
    });
    rows.value = (data.payload || []).map(r => ({
      id: r.id,
      departmentId: r.department_id,
      departmentName: r.department_name,
      shopId: r.shop_id,
      shopName: r.shop_name,
      expenseDate: r.expense_date,
      category: r.category,
      subject: r.subject,
      amount: r.amount,
      currency: r.currency,
      amountCny: r.amount_cny,
      remark: r.remark,
      files: r.files || [],
    }));
    totalCny.value = num(data.meta?.total_cny);
    editableDeptIds.value = data.meta?.editable_department_ids ?? [];
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

watch(() => [filters.value.month, filters.value.departmentId], load);

// ---- 录入 ----
const showForm = ref(false);
// 票据选填：新选的走 multipart 追加，编辑时可勾删已有的（remove_file_ids）。
const pendingFiles = ref([]);
const existingFiles = ref([]);
const removeFileIds = ref([]);
const fileInputRef = ref(null);
const emptyForm = () => ({
  id: null,
  departmentId: departments.value[0]?.id || '',
  shopId: '',
  expenseDate: new Date().toISOString().slice(0, 10),
  category: '广告花费',
  subject: '',
  amount: 0,
  currency: 'CNY',
  remark: '',
});
const form = ref(emptyForm());
const isEdit = computed(() => form.value.id != null);

// 店铺选填：只列当前所选部门下的店铺，避免把别的部门店铺挂错账。
const shopOptions = computed(() => [
  { value: '', label: '不挂店铺（部门开销）' },
  ...shops.value
    .filter(
      s =>
        !form.value.departmentId || s.departmentId === form.value.departmentId
    )
    .map(s => ({ value: s.id, label: s.name })),
]);

const openNew = () => {
  if (!departments.value.length) {
    useAlert('还没有 TK 部门，请先到「部门管理」创建');
    return;
  }
  form.value = emptyForm();
  pendingFiles.value = [];
  existingFiles.value = [];
  removeFileIds.value = [];
  showForm.value = true;
};

const openEdit = r => {
  form.value = {
    id: r.id,
    departmentId: r.departmentId,
    shopId: r.shopId || '',
    expenseDate: r.expenseDate,
    category: r.category,
    subject: r.subject,
    amount: num(r.amount),
    currency: r.currency,
    remark: r.remark || '',
  };
  pendingFiles.value = [];
  existingFiles.value = [...(r.files || [])];
  removeFileIds.value = [];
  showForm.value = true;
};

const onPickFiles = event => {
  pendingFiles.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removePendingFile = i => pendingFiles.value.splice(i, 1);
const removeExistingFile = f => {
  removeFileIds.value.push(f.id);
  existingFiles.value = existingFiles.value.filter(x => x.id !== f.id);
};

const invalid = computed(
  () =>
    !form.value.departmentId ||
    !form.value.subject.trim() ||
    !(num(form.value.amount) > 0)
);

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    department_id: form.value.departmentId,
    shop_id: form.value.shopId || null,
    expense_date: form.value.expenseDate,
    category: form.value.category,
    subject: form.value.subject.trim(),
    amount: num(form.value.amount),
    currency: form.value.currency,
    remark: form.value.remark.trim() || null,
  };
  try {
    const hasFileChange =
      pendingFiles.value.length > 0 || removeFileIds.value.length > 0;
    if (hasFileChange) {
      const fd = new FormData();
      Object.entries(payload).forEach(([k, v]) =>
        fd.append(`expense[${k}]`, v ?? '')
      );
      pendingFiles.value.forEach(f => fd.append('files[]', f));
      removeFileIds.value.forEach(id => fd.append('remove_file_ids[]', id));
      if (isEdit.value) {
        await TiktokExpensesAPI.updateWithFiles(form.value.id, fd);
      } else {
        await TiktokExpensesAPI.createWithFiles(fd);
      }
    } else if (isEdit.value) {
      await TiktokExpensesAPI.update(form.value.id, { expense: payload });
    } else {
      await TiktokExpensesAPI.create({ expense: payload });
    }
    showForm.value = false;
    useAlert(isEdit.value ? '已保存' : '已记账');
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  }
};

const remove = async r => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除「${r.subject}」这笔支出？删除后不可恢复。`))
    return;
  try {
    await TiktokExpensesAPI.delete(r.id);
    useAlert('已删除');
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '删除失败');
  }
};

onMounted(async () => {
  const [s, d] = await Promise.all([
    shopsStore.get().catch(() => []),
    deptStore.get().catch(() => []),
  ]);
  shops.value = s || shopsStore.getRecords || [];
  departments.value = d || deptStore.getRecords || [];
  load();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto sm:px-8 sm:py-6 max-w-7xl">
      <div class="flex flex-wrap items-center gap-3 mb-6">
        <div class="flex-1 min-w-0">
          <h1 class="text-xl font-semibold text-n-slate-12">支出台账</h1>
          <p class="mt-1 text-sm text-n-slate-11">
            店铺运营与部门日常开销，外币按记账当时汇率折算 RMB。
          </p>
        </div>
        <MonthPicker v-model="filters.month" trigger-class="w-36 h-9" />
        <SelectCard
          v-model="filters.departmentId"
          :options="departmentFilterOptions"
          trigger-class="w-36"
        />
        <Button
          variant="outline"
          color="slate"
          size="sm"
          class="btn-ink"
          icon="i-lucide-download"
          label="导出报表"
          :is-loading="exporting"
          :disabled="exporting || !rows.length"
          @click="exportXlsx"
        />
        <Button
          v-if="canCreate"
          color="iris"
          size="sm"
          icon="i-lucide-plus"
          label="新增"
          @click="openNew"
        />
      </div>

      <!-- 汇总 -->
      <div
        class="flex flex-wrap items-center gap-4 px-4 py-3 mb-4 rounded-xl bg-n-alpha-1"
      >
        <div class="flex items-baseline gap-2">
          <span class="text-sm text-n-slate-11">本月支出合计</span>
          <b class="text-xl text-n-slate-12">{{ cny(totalCny) }}</b>
          <span class="text-xs text-n-slate-10">{{ rows.length }} 笔</span>
        </div>
        <div class="flex flex-wrap items-center gap-3 text-xs text-n-slate-11">
          <span v-for="[name, sum] in byCategory" :key="name">
            {{ name }}
            <b class="text-n-slate-12">{{ cny(sum) }}</b>
          </span>
        </div>
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <div v-else class="overflow-x-auto border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="px-4 py-3 font-medium text-left">日期</th>
              <th class="px-4 py-3 font-medium text-left">部门 / 店铺</th>
              <th class="px-4 py-3 font-medium text-left">类别</th>
              <th class="px-4 py-3 font-medium text-left">事由</th>
              <th class="px-4 py-3 font-medium text-right">金额</th>
              <th class="px-4 py-3 font-medium text-right">折RMB</th>
              <th class="px-4 py-3 font-medium text-left">备注</th>
              <th class="px-4 py-3 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="r in rows"
              :key="r.id"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-4 py-3 whitespace-nowrap text-n-slate-11">
                {{ r.expenseDate }}
              </td>
              <td class="px-4 py-3 text-n-slate-12">
                {{ r.departmentName }}
                <span v-if="r.shopName" class="text-n-slate-10">
                  · {{ r.shopName }}
                </span>
              </td>
              <td class="px-4 py-3 text-n-slate-11">{{ r.category }}</td>
              <td class="px-4 py-3 text-n-slate-12">{{ r.subject }}</td>
              <td class="px-4 py-3 text-right tabular-nums text-n-slate-11">
                {{ r.currency }} {{ num(r.amount).toLocaleString('zh-CN') }}
              </td>
              <td
                class="px-4 py-3 font-medium text-right tabular-nums text-n-slate-12"
              >
                {{ cny(r.amountCny) }}
              </td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ r.remark }}
                <button
                  v-for="f in r.files"
                  :key="f.id"
                  type="button"
                  class="ml-1 text-xs text-n-iris-11 hover:underline"
                  @click="previewFile = f"
                >
                  票据
                </button>
              </td>
              <td class="px-4 py-3 text-right whitespace-nowrap">
                <template v-if="canEditDept(r.departmentId)">
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
                </template>
                <span v-else class="text-xs text-n-slate-10">只读</span>
              </td>
            </tr>
            <tr v-if="!rows.length">
              <td colspan="8" class="px-4 py-12 text-center text-n-slate-10">
                本月还没有支出记录{{
                  canCreate ? '，点右上角「新增」开始记。' : '。'
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <AttachmentPreview :file="previewFile" @close="previewFile = null" />

    <!-- 录入弹窗 -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showForm = false"
    >
      <div
        class="w-full max-w-[95vw] sm:max-w-xl p-4 sm:p-6 overflow-y-auto max-h-[90vh] rounded-2xl bg-n-solid-1 shadow-xl"
      >
        <h2 class="mb-4 text-lg font-semibold text-n-slate-12">
          {{ isEdit ? '编辑支出' : '新增支出' }}
        </h2>

        <div class="grid grid-cols-2 gap-4">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">部门</span>
            <SelectCard
              v-model="form.departmentId"
              :options="departmentOptions"
              block
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">店铺（选填）</span>
            <SelectCard v-model="form.shopId" :options="shopOptions" block />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">日期</span>
            <DatePicker v-model="form.expenseDate" block />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">类别</span>
            <SelectCard
              v-model="form.category"
              :options="CATEGORIES.map(c => ({ value: c, label: c }))"
              block
            />
          </label>
          <label class="flex flex-col col-span-2 gap-1">
            <span class="text-xs text-n-slate-11">事由</span>
            <input
              v-model="form.subject"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">金额</span>
            <input
              v-model.number="form.amount"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">币种</span>
            <SelectCard
              v-model="form.currency"
              :options="CURRENCIES.map(c => ({ value: c, label: c }))"
              block
            />
          </label>
          <label class="flex flex-col col-span-2 gap-1">
            <span class="text-xs text-n-slate-11">备注（选填）</span>
            <input
              v-model="form.remark"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </div>

        <div class="flex flex-col gap-1 mt-4">
          <span class="text-xs text-n-slate-11">票据 / 截图（选填）</span>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            accept="image/*,.pdf"
            class="hidden"
            @change="onPickFiles"
          />
          <button
            type="button"
            class="inline-flex items-center self-start gap-1.5 px-3 h-9 text-sm border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="fileInputRef?.click()"
          >
            <span class="i-lucide-plus size-4" />
            添加票据
          </button>
          <div
            v-for="f in existingFiles"
            :key="f.id"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <button
              type="button"
              class="truncate text-n-iris-11 hover:underline"
              @click="previewFile = f"
            >
              {{ f.filename }}
            </button>
            <button
              type="button"
              class="text-n-ruby-11"
              @click="removeExistingFile(f)"
            >
              删除
            </button>
          </div>
          <div
            v-for="(f, i) in pendingFiles"
            :key="i"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span class="truncate">{{ f.name }}</span>
            <button
              type="button"
              class="text-n-ruby-11"
              @click="removePendingFile(i)"
            >
              移除
            </button>
          </div>
        </div>

        <p class="mt-3 text-xs text-n-slate-10">
          非 CNY 金额的 RMB 换算于保存时按实时汇率计算。
        </p>

        <div class="flex justify-end gap-2 mt-6">
          <Button
            variant="ghost"
            color="slate"
            label="取消"
            @click="showForm = false"
          />
          <Button
            color="iris"
            label="保存"
            :disabled="invalid"
            @click="submit"
          />
        </div>
      </div>
    </div>
  </div>
</template>
