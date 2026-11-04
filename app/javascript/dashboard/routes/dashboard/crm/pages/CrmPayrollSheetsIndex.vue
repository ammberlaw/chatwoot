<script setup>
// 月度工资表列表：财务/人事核算入口。
// 这页只列表＋导入＋删，明细在详情页改；确认封账后不可改（后端也挡着）。
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import { useAlert } from 'dashboard/composables';
import PayrollAPI from 'dashboard/api/crm/payrollSheets';
import Button from 'dashboard/components-next/button/Button.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { fmtYuan } from 'dashboard/helper/crmMoney';

const router = useRouter();

const rows = ref([]);
const loading = ref(false);
const monthFilter = ref('');
const templateFilter = ref('');
const importDialog = ref(null);
const importing = ref(false);
const fileInput = ref(null);
const draft = ref({ month: '', template: '', title: '', file: null });

const TEMPLATES = [
  { value: '', label: '全部类型' },
  { value: 'WORKSHOP', label: '车间' },
  { value: 'OFFICE', label: '办公室 / 业务' },
];
// 导入时可以不选，让系统按表头自己认（有「工龄补贴」是车间，有「绩效工资」是办公室）。
const IMPORT_TEMPLATES = [
  { value: '', label: '自动识别' },
  { value: 'WORKSHOP', label: '车间' },
  { value: 'OFFICE', label: '办公室 / 业务' },
];

const load = async () => {
  loading.value = true;
  try {
    const { data } = await PayrollAPI.get({
      month: monthFilter.value,
      template: templateFilter.value,
      per_page: 50,
    });
    rows.value = camelcaseKeys(data.payload || [], { deep: true });
  } catch (e) {
    rows.value = [];
    useAlert(e?.response?.data?.error || '工资表加载失败');
  } finally {
    loading.value = false;
  }
};

const total = computed(() => rows.value.length);

const openImport = () => {
  const d = new Date();
  const m = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
  draft.value = { month: m, template: '', title: '', file: null };
  importDialog.value?.open();
};

const pickFile = e => {
  draft.value.file = e.target.files?.[0] || null;
};

const doImport = async () => {
  if (!draft.value.file) return useAlert('请先选择 Excel 文件');
  importing.value = true;
  try {
    const { data } = await PayrollAPI.import(draft.value.file, {
      periodMonth: `${draft.value.month}-01`,
      template: draft.value.template,
      title: draft.value.title.trim(),
    });
    importDialog.value?.close();
    const extra = data.adjusted
      ? `，其中 ${data.adjusted} 人与原表有差额已记入「个别调整」`
      : '';
    useAlert(`已导入 ${data.count} 人${extra}`);
    await load();
    router.push({ name: 'crm_payroll_sheet_detail', query: { id: data.id } });
  } catch (e) {
    useAlert(e?.response?.data?.error || '导入失败');
  } finally {
    importing.value = false;
  }
  return undefined;
};

const openSheet = row =>
  router.push({ name: 'crm_payroll_sheet_detail', query: { id: row.id } });

const remove = async row => {
  if (
    !window.confirm(
      `确定删除「${row.title}」？整张表连同 ${row.itemCount} 行明细一起删除。`
    )
  )
    return;
  try {
    await PayrollAPI.delete(row.id);
    useAlert('已删除');
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '删除失败');
  }
};

const fmtMonth = v => (v ? String(v).slice(0, 7) : '—');

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1">
    <header
      class="flex flex-wrap items-center justify-between gap-3 px-5 py-6 sm:px-8"
    >
      <h1 class="text-heading-1 text-n-slate-12">工资表</h1>
      <Button
        label="导入工资表"
        icon="i-lucide-upload"
        color="slate"
        class="!bg-n-slate-12 !text-n-solid-1 hover:enabled:!bg-n-slate-11"
        @click="openImport"
      />
    </header>

    <div class="flex items-center gap-2 px-5 pb-4 sm:px-8 shrink-0">
      <MonthPicker
        v-model="monthFilter"
        tone="slate"
        trigger-class="w-36 h-8"
        placeholder="全部月份"
        @change="load"
      />
      <SelectCard
        v-model="templateFilter"
        :options="TEMPLATES"
        trigger-class="w-32 !h-8"
        placeholder="全部类型"
        @update:model-value="load"
      />
      <span v-if="total" class="text-label-small text-n-slate-11">
        共 {{ total }} 张
      </span>
    </div>

    <div class="flex-1 px-5 overflow-auto sm:px-8">
      <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <p
        v-else-if="!rows.length"
        class="py-10 text-sm text-center text-n-slate-10"
      >
        还没有工资表，点右上角「导入工资表」开始
      </p>
      <table v-else class="w-max min-w-full text-sm">
        <thead>
          <tr class="text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-3 py-2 font-medium whitespace-nowrap">月份</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">名称</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">类型</th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              人数
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              应发合计
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              实发合计
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">状态</th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">制表</th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.id"
            class="border-b cursor-pointer border-n-weak hover:bg-n-alpha-1"
            @click="openSheet(row)"
          >
            <td class="px-3 py-2 tabular-nums text-n-slate-12">
              {{ fmtMonth(row.periodMonth) }}
            </td>
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ row.title }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">{{ row.templateLabel }}</td>
            <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
              {{ row.itemCount }}
            </td>
            <td class="px-3 py-2 text-right tabular-nums text-n-slate-12">
              {{ fmtYuan(row.totalGrossMicros) }}
            </td>
            <td
              class="px-3 py-2 font-medium text-right tabular-nums text-n-slate-12"
            >
              {{ fmtYuan(row.totalNetMicros) }}
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <span
                class="px-2 py-0.5 rounded text-label-small"
                :class="
                  row.status === 'CONFIRMED'
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-amber-3 text-n-slate-12'
                "
              >
                {{ row.statusLabel }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ row.createdByName || '—' }}
            </td>
            <td class="px-3 py-2" @click.stop>
              <Button
                v-if="row.editable"
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                @click="remove(row)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="importDialog"
      overflow-y-auto
      width="md"
      title="导入工资表"
      confirm-button-label="开始导入"
      :is-loading="importing"
      @confirm="doImport"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">月份 *</label>
          <MonthPicker
            v-model="draft.month"
            tone="slate"
            :clearable="false"
            trigger-class="w-full h-10"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">表格类型</label>
          <SelectCard
            v-model="draft.template"
            :options="IMPORT_TEMPLATES"
            trigger-class="w-full !h-10"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">名称</label>
          <Input v-model="draft.title" placeholder="留空自动命名" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-label text-n-slate-12">Excel 文件 *</label>
          <input
            ref="fileInput"
            type="file"
            accept=".xlsx,.xls"
            class="reset-base text-sm text-n-slate-12"
            @change="pickFile"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
