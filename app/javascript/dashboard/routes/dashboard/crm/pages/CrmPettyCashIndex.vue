<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import PettyCashAPI from 'dashboard/api/crm/pettyCash';
import OrgDepartmentAPI from 'dashboard/api/org/departments';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';

// 备用金台账：一个部门/项目一本账（对应原 Excel 的一个 sheet），本下挂收支流水，
// 结余 = 期初 + 存入 − 支出，列表按日期正序逐行滚动（与 Excel 口径一致）。
const CHANNELS = ['现金', '支付宝', '微信', '银行', '其他'];
const CATEGORIES = ['差旅', '招待', '办公', '交通', '其他'];

const books = ref([]);
const activeBookId = ref(null);
const entries = ref([]);
const opening = ref(0);
const month = ref('');
const loading = ref(false);
// canManage：建/改/删台账本（财务与管理员）；canRecord：在当前这本账上记流水
// （财务与管理员全部可记，部门负责人只可记自己带的部门那本）。后端同口径再校验一次。
const canManage = ref(false);
// 绑部门决定两件事：部门负责人能否看/记这本账，以及审批通过后往哪本账落账。
const departments = ref([]);

const activeBook = computed(
  () => books.value.find(b => b.id === activeBookId.value) || null
);
const canRecord = computed(() => activeBook.value?.can_record === true);
const bookOptions = computed(() =>
  books.value.map(b => ({ value: String(b.id), label: b.name }))
);
const departmentOptions = computed(() => [
  { value: '', label: '不绑部门（项目型台账）' },
  ...departments.value.map(d => ({ value: String(d.id), label: d.name })),
]);

const emptyHint = computed(() => {
  if (!activeBookId.value) {
    return canManage.value
      ? '还没有台账本，点右上角「新建台账本」创建（如：深圳外贸部门）。'
      : '还没有你可查看的台账本，请让财务先建好并绑定你的部门。';
  }
  return canRecord.value
    ? '这本账还没有流水，点右上角「记一笔」开始记。'
    : '这本账还没有流水。';
});

const money = v =>
  Number(v || 0).toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

// 逐行结余：从期初开始按顺序累加，存入加、支出减——跟 Excel 的「结余」列一致。
const rows = computed(() => {
  let running = Number(opening.value || 0);
  return entries.value.map(e => {
    running += e.direction === 'IN' ? Number(e.amount) : -Number(e.amount);
    return { ...e, balance: running };
  });
});

const totals = computed(() => ({
  in: entries.value
    .filter(e => e.direction === 'IN')
    .reduce((s, e) => s + Number(e.amount), 0),
  out: entries.value
    .filter(e => e.direction === 'OUT')
    .reduce((s, e) => s + Number(e.amount), 0),
}));

const fetchBooks = async () => {
  try {
    const { data } = await PettyCashAPI.books();
    books.value = data.payload || [];
    canManage.value = data.meta?.can_manage === true;
    if (!activeBookId.value && books.value.length) {
      activeBookId.value = books.value[0].id;
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载台账失败');
  }
};

const fetchDepartments = async () => {
  try {
    const { data } = await OrgDepartmentAPI.get();
    departments.value = data.payload || [];
  } catch {
    departments.value = [];
  }
};

const fetchEntries = async () => {
  if (!activeBookId.value) {
    entries.value = [];
    return;
  }
  loading.value = true;
  try {
    const params = month.value ? { month: month.value } : {};
    const { data } = await PettyCashAPI.entries(activeBookId.value, params);
    entries.value = data.payload || [];
    opening.value = Number(data.meta?.opening || 0);
  } catch (error) {
    useAlert(error?.response?.data?.error || '加载流水失败');
  } finally {
    loading.value = false;
  }
};

watch([activeBookId, month], fetchEntries);

// ---- 流水录入 ----
const entryDialogRef = ref(null);
const editingEntryId = ref(null);
const blankEntry = () => ({
  entryDate: new Date().toISOString().slice(0, 10),
  direction: 'OUT',
  amount: '',
  subject: '',
  channel: '',
  category: '',
  remark: '',
});
const entryForm = ref(blankEntry());
const entryFiles = ref([]);
const fileInputRef = ref(null);

const entryInvalid = computed(
  () =>
    !entryForm.value.entryDate ||
    !entryForm.value.subject.trim() ||
    !(Number(entryForm.value.amount) > 0)
);

const openCreateEntry = () => {
  editingEntryId.value = null;
  entryForm.value = blankEntry();
  entryFiles.value = [];
  entryDialogRef.value?.open();
};

const openEditEntry = entry => {
  editingEntryId.value = entry.id;
  entryForm.value = {
    entryDate: entry.entry_date,
    direction: entry.direction,
    amount: String(entry.amount),
    subject: entry.subject,
    channel: entry.channel || '',
    category: entry.category || '',
    remark: entry.remark || '',
  };
  entryFiles.value = [];
  entryDialogRef.value?.open();
};

const onPickFiles = event => {
  entryFiles.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeFile = i => entryFiles.value.splice(i, 1);

const buildEntryPayload = () => ({
  entry_date: entryForm.value.entryDate,
  direction: entryForm.value.direction,
  amount: Number(entryForm.value.amount),
  subject: entryForm.value.subject.trim(),
  channel: entryForm.value.channel || null,
  category: entryForm.value.category || null,
  remark: entryForm.value.remark.trim() || null,
});

const submitEntry = async () => {
  if (entryInvalid.value) return;
  const payload = buildEntryPayload();
  try {
    if (entryFiles.value.length) {
      const fd = new FormData();
      Object.entries(payload).forEach(([k, v]) =>
        fd.append(`entry[${k}]`, v ?? '')
      );
      entryFiles.value.forEach(f => fd.append('files[]', f));
      if (editingEntryId.value) {
        await PettyCashAPI.updateEntryWithFiles(
          activeBookId.value,
          editingEntryId.value,
          fd
        );
      } else {
        await PettyCashAPI.createEntryWithFiles(activeBookId.value, fd);
      }
    } else if (editingEntryId.value) {
      await PettyCashAPI.updateEntry(
        activeBookId.value,
        editingEntryId.value,
        payload
      );
    } else {
      await PettyCashAPI.createEntry(activeBookId.value, payload);
    }
    entryDialogRef.value?.close();
    useAlert(editingEntryId.value ? '已保存' : '已记账');
    await Promise.all([fetchEntries(), fetchBooks()]);
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

const removeEntry = async entry => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除「${entry.subject}」这笔流水？删除后不可恢复。`))
    return;
  try {
    await PettyCashAPI.deleteEntry(activeBookId.value, entry.id);
    useAlert('已删除');
    await Promise.all([fetchEntries(), fetchBooks()]);
  } catch (error) {
    useAlert(error?.response?.data?.error || '删除失败');
  }
};

// ---- 台账本维护 ----
const bookDialogRef = ref(null);
const editingBookId = ref(null);
const bookForm = ref({
  name: '',
  departmentId: '',
  openingBalance: '0',
  remark: '',
});

const openCreateBook = () => {
  editingBookId.value = null;
  bookForm.value = {
    name: '',
    departmentId: '',
    openingBalance: '0',
    remark: '',
  };
  bookDialogRef.value?.open();
};

const openEditBook = () => {
  if (!activeBook.value) return;
  editingBookId.value = activeBook.value.id;
  bookForm.value = {
    name: activeBook.value.name,
    departmentId: activeBook.value.org_department_id
      ? String(activeBook.value.org_department_id)
      : '',
    openingBalance: String(activeBook.value.opening_balance ?? '0'),
    remark: activeBook.value.remark || '',
  };
  bookDialogRef.value?.open();
};

const bookInvalid = computed(() => !bookForm.value.name.trim());

const submitBook = async () => {
  if (bookInvalid.value) return;
  const payload = {
    name: bookForm.value.name.trim(),
    // 清空要显式送 null，undefined 会被 JSON 丢掉、后端保留原值。
    org_department_id: bookForm.value.departmentId
      ? Number(bookForm.value.departmentId)
      : null,
    opening_balance: Number(bookForm.value.openingBalance || 0),
    remark: bookForm.value.remark.trim() || null,
  };
  try {
    if (editingBookId.value) {
      await PettyCashAPI.updateBook(editingBookId.value, payload);
    } else {
      const { data } = await PettyCashAPI.createBook(payload);
      activeBookId.value = data.id;
    }
    bookDialogRef.value?.close();
    useAlert('已保存');
    await fetchBooks();
    await fetchEntries();
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  }
};

onMounted(async () => {
  await fetchBooks();
  await fetchEntries();
  if (canManage.value) fetchDepartments();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="w-full px-4 py-4 mx-auto max-w-6xl sm:px-8 sm:py-6">
      <div class="flex items-center justify-between mb-1">
        <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
          备用金台账
        </h1>
        <div class="flex items-center gap-2">
          <Button
            v-if="canManage"
            label="新建台账本"
            variant="outline"
            size="sm"
            @click="openCreateBook"
          />
          <Button
            v-if="canRecord"
            label="记一笔"
            size="sm"
            color="iris"
            :disabled="!activeBookId"
            @click="openCreateEntry"
          />
        </div>
      </div>
      <p class="mb-5 text-sm text-n-slate-11">
        一个部门或项目一本账，结余 = 期初 + 存入 −
        支出。备用金申请与费用报销审批通过后自动落账。
      </p>

      <!-- 选本 + 月份 + 结余 -->
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <SelectCard
          :model-value="activeBookId ? String(activeBookId) : ''"
          :options="bookOptions"
          trigger-class="w-52"
          @update:model-value="v => (activeBookId = Number(v))"
        />
        <!-- MonthPicker 默认 h-10，比 SelectCard 的 h-9 高一截，显式压平对齐。 -->
        <MonthPicker v-model="month" trigger-class="w-44 h-9" clearable />
        <Button
          v-if="activeBook && canManage"
          label="本账设置"
          variant="ghost"
          size="xs"
          @click="openEditBook"
        />
        <div class="flex-1" />
        <div v-if="activeBook" class="flex items-center gap-4 text-sm">
          <span class="text-n-slate-11">
            存入
            <b class="text-n-teal-11">{{ money(totals.in) }}</b>
          </span>
          <span class="text-n-slate-11">
            支出
            <b class="text-n-ruby-11">{{ money(totals.out) }}</b>
          </span>
          <span class="text-n-slate-11">
            当前结余
            <b class="text-base text-n-slate-12">
              {{ money(activeBook.balance) }}
            </b>
          </span>
        </div>
      </div>

      <!-- 流水表 -->
      <div class="overflow-x-auto border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-alpha-1 text-n-slate-11">
            <tr>
              <th class="px-3 py-2.5 font-medium text-left">日期</th>
              <th class="px-3 py-2.5 font-medium text-left">事由</th>
              <th class="px-3 py-2.5 font-medium text-right">存入</th>
              <th class="px-3 py-2.5 font-medium text-right">支出</th>
              <th class="px-3 py-2.5 font-medium text-right">结余</th>
              <th class="px-3 py-2.5 font-medium text-left">渠道</th>
              <th class="px-3 py-2.5 font-medium text-left">情况说明</th>
              <th class="px-3 py-2.5 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="opening" class="border-t border-n-weak text-n-slate-11">
              <td class="px-3 py-2.5" colspan="4">期初余额</td>
              <td class="px-3 py-2.5 font-medium text-right">
                {{ money(opening) }}
              </td>
              <td class="px-3 py-2.5" colspan="3" />
            </tr>
            <tr
              v-for="row in rows"
              :key="row.id"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2.5 whitespace-nowrap text-n-slate-11">
                {{ row.entry_date }}
              </td>
              <td class="px-3 py-2.5 text-n-slate-12">
                {{ row.subject }}
                <span
                  v-if="row.oa_approval_request_id"
                  class="ml-1 text-xs text-n-iris-11"
                >
                  审批
                </span>
                <span v-if="row.category" class="ml-1 text-xs text-n-slate-10">
                  {{ row.category }}
                </span>
              </td>
              <td class="px-3 py-2.5 text-right text-n-teal-11">
                {{ row.direction === 'IN' ? money(row.amount) : '' }}
              </td>
              <td class="px-3 py-2.5 text-right text-n-ruby-11">
                {{ row.direction === 'OUT' ? money(row.amount) : '' }}
              </td>
              <td class="px-3 py-2.5 font-medium text-right text-n-slate-12">
                {{ money(row.balance) }}
              </td>
              <td class="px-3 py-2.5 text-n-slate-11">{{ row.channel }}</td>
              <td class="px-3 py-2.5 text-n-slate-11">
                {{ row.remark }}
                <a
                  v-for="f in row.files"
                  :key="f.id"
                  :href="f.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="ml-1 text-xs text-n-iris-11"
                >
                  票据
                </a>
              </td>
              <td class="px-3 py-2.5 text-right whitespace-nowrap">
                <template v-if="canRecord">
                  <Button
                    label="改"
                    variant="ghost"
                    size="xs"
                    @click="openEditEntry(row)"
                  />
                  <Button
                    label="删"
                    variant="ghost"
                    size="xs"
                    color="ruby"
                    @click="removeEntry(row)"
                  />
                </template>
                <span v-else class="text-xs text-n-slate-10">只读</span>
              </td>
            </tr>
            <tr v-if="!rows.length && !loading">
              <td class="px-3 py-8 text-center text-n-slate-11" colspan="8">
                {{ emptyHint }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 记一笔 -->
    <Dialog
      ref="entryDialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      :title="editingEntryId ? '修改流水' : '记一笔'"
      :disable-confirm-button="entryInvalid"
      @confirm="submitEntry"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              日期 <span class="text-n-ruby-11">*</span>
            </label>
            <DatePicker v-model="entryForm.entryDate" block />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">收支方向</label>
            <SelectCard
              v-model="entryForm.direction"
              :options="[
                { value: 'OUT', label: '支出' },
                { value: 'IN', label: '存入' },
              ]"
              block
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            事由 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="entryForm.subject"
            placeholder="如：TK第三方人员费用日结 / 备用金领用"
          />
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              金额 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="entryForm.amount" type="number" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">渠道</label>
            <SelectCard
              v-model="entryForm.channel"
              :options="[
                { value: '', label: '不填' },
                ...CHANNELS.map(c => ({ value: c, label: c })),
              ]"
              block
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              类别
              <span class="text-n-slate-10">（选填）</span>
            </label>
            <SelectCard
              v-model="entryForm.category"
              :options="[
                { value: '', label: '不填' },
                ...CATEGORIES.map(c => ({ value: c, label: c })),
              ]"
              block
            />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">情况说明</label>
          <Input v-model="entryForm.remark" placeholder="备注，选填" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            票据
            <span class="text-n-slate-10">（选填）</span>
          </label>
          <!-- 与审批页同款：藏原生 input，用统一样式的按钮触发，别露系统灰按钮。 -->
          <input
            ref="fileInputRef"
            type="file"
            multiple
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
            v-for="(f, i) in entryFiles"
            :key="i"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span class="truncate">{{ f.name }}</span>
            <button type="button" class="text-n-ruby-11" @click="removeFile(i)">
              移除
            </button>
          </div>
        </div>
      </div>
    </Dialog>

    <!-- 台账本 -->
    <Dialog
      ref="bookDialogRef"
      :dismissible="false"
      width="lg"
      confirm-button-color="iris"
      :title="editingBookId ? '台账本设置' : '新建台账本'"
      :disable-confirm-button="bookInvalid"
      @confirm="submitBook"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            名称 <span class="text-n-ruby-11">*</span>
          </label>
          <Input
            v-model="bookForm.name"
            placeholder="如：深圳外贸部门 / AI社媒GEO项目"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">所属部门</label>
          <SelectCard
            v-model="bookForm.departmentId"
            :options="departmentOptions"
            block
          />
          <span class="text-xs text-n-slate-11">
            绑定后，该部门负责人可查看并记这本账；备用金申请/费用报销审批通过也会自动落到这本。
          </span>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">期初余额</label>
          <Input v-model="bookForm.openingBalance" type="number" />
          <span class="text-xs text-n-slate-11">
            从 Excel 搬过来时，填当前结余作为期初，之后的流水在系统里记。
          </span>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="bookForm.remark" placeholder="选填" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
