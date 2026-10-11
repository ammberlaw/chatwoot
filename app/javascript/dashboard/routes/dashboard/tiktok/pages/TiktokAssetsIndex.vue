<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import TiktokAssetsAPI from 'dashboard/api/tiktok/assets';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import AttachmentPreview from 'dashboard/components-next/attachment/AttachmentPreview.vue';

// TK 固定资产登记：只记「有什么、谁在用、在哪、多少钱」，不算折旧（折旧归 ERP）。
const CATEGORIES = [
  '拍摄设备',
  '电脑',
  '手机',
  '灯光音响',
  '家具',
  '样机',
  '其它',
];
const STATUSES = [
  { value: 'IN_USE', label: '在用' },
  { value: 'IDLE', label: '闲置' },
  { value: 'REPAIR', label: '维修中' },
  { value: 'SCRAPPED', label: '已报废' },
];

// 附件在线预览（图片/PDF 直接看，其它给下载）。
const previewFile = ref(null);

const deptStore = useTiktokDepartmentsStore();

const departments = ref([]);
const agents = ref([]);
const rows = ref([]);
const totalAmount = ref(0);
const editableDeptIds = ref([]);
const loading = ref(false);
const filters = ref({ departmentId: '', status: '' });

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
const statusFilterOptions = computed(() => [
  { value: '', label: '全部状态' },
  ...STATUSES,
]);
const holderOptions = computed(() => [
  { value: '', label: '未指定' },
  ...agents.value.map(a => ({ value: a.id, label: a.name })),
]);

// 顶部按状态汇总，一眼看到在用/闲置各多少台。
const byStatus = computed(() =>
  STATUSES.map(s => ({
    label: s.label,
    count: rows.value.filter(r => r.status === s.value).length,
  })).filter(x => x.count > 0)
);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await TiktokAssetsAPI.get({
      department_id: filters.value.departmentId,
      status: filters.value.status,
    });
    rows.value = (data.payload || []).map(a => ({
      id: a.id,
      departmentId: a.department_id,
      departmentName: a.department_name,
      name: a.name,
      code: a.code,
      category: a.category,
      purchasedOn: a.purchased_on,
      amount: a.amount,
      holderId: a.holder_id,
      holderName: a.holder_name,
      location: a.location,
      status: a.status,
      statusLabel: a.status_label,
      remark: a.remark,
      files: a.files || [],
    }));
    totalAmount.value = num(data.meta?.total_amount);
    editableDeptIds.value = data.meta?.editable_department_ids ?? [];
  } catch (e) {
    useAlert(e?.response?.data?.error || '加载失败');
  } finally {
    loading.value = false;
  }
};

watch(() => [filters.value.departmentId, filters.value.status], load);

// ---- 登记 ----
const showForm = ref(false);
const pendingFiles = ref([]);
const fileInputRef = ref(null);
const emptyForm = () => ({
  id: null,
  departmentId: departments.value[0]?.id || '',
  name: '',
  code: '',
  category: '拍摄设备',
  purchasedOn: new Date().toISOString().slice(0, 10),
  amount: 0,
  holderId: '',
  location: '',
  status: 'IN_USE',
  remark: '',
});
const form = ref(emptyForm());
const isEdit = computed(() => form.value.id != null);
const invalid = computed(
  () => !form.value.departmentId || !form.value.name.trim()
);

const openNew = () => {
  if (!departments.value.length) {
    useAlert('还没有 TK 部门，请先到「部门管理」创建');
    return;
  }
  form.value = emptyForm();
  pendingFiles.value = [];
  showForm.value = true;
};

const openEdit = a => {
  form.value = {
    id: a.id,
    departmentId: a.departmentId,
    name: a.name,
    code: a.code || '',
    category: a.category || '拍摄设备',
    purchasedOn: a.purchasedOn || '',
    amount: num(a.amount),
    holderId: a.holderId || '',
    location: a.location || '',
    status: a.status,
    remark: a.remark || '',
  };
  pendingFiles.value = [];
  showForm.value = true;
};

const onPickFiles = event => {
  pendingFiles.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeFile = i => pendingFiles.value.splice(i, 1);

const submit = async () => {
  if (invalid.value) return;
  const payload = {
    department_id: form.value.departmentId,
    name: form.value.name.trim(),
    code: form.value.code.trim() || null,
    category: form.value.category,
    purchased_on: form.value.purchasedOn || null,
    amount: num(form.value.amount),
    holder_id: form.value.holderId || null,
    location: form.value.location.trim() || null,
    status: form.value.status,
    remark: form.value.remark.trim() || null,
  };
  try {
    if (pendingFiles.value.length) {
      const fd = new FormData();
      Object.entries(payload).forEach(([k, v]) =>
        fd.append(`asset[${k}]`, v ?? '')
      );
      pendingFiles.value.forEach(f => fd.append('files[]', f));
      if (isEdit.value) {
        await TiktokAssetsAPI.updateWithFiles(form.value.id, fd);
      } else {
        await TiktokAssetsAPI.createWithFiles(fd);
      }
    } else if (isEdit.value) {
      await TiktokAssetsAPI.update(form.value.id, { asset: payload });
    } else {
      await TiktokAssetsAPI.create({ asset: payload });
    }
    showForm.value = false;
    useAlert(isEdit.value ? '已保存' : '已登记');
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  }
};

const remove = async a => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`确定删除资产「${a.name}」？删除后不可恢复。`)) return;
  try {
    await TiktokAssetsAPI.delete(a.id);
    useAlert('已删除');
    load();
  } catch (e) {
    useAlert(e?.response?.data?.error || '删除失败');
  }
};

onMounted(async () => {
  const d = await deptStore.get().catch(() => []);
  departments.value = d || deptStore.getRecords || [];
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
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
          <h1 class="text-xl font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">固定资产登记</h1>
          <p class="mt-1 text-sm text-n-slate-11">
            设备/电脑/手机等资产的登记台账：谁在用、放在哪、什么状态。
          </p>
        </div>
        <SelectCard
          v-model="filters.departmentId"
          :options="departmentFilterOptions"
          trigger-class="w-36"
        />
        <SelectCard
          v-model="filters.status"
          :options="statusFilterOptions"
          trigger-class="w-32"
        />
        <Button
          v-if="canCreate"
          color="iris"
          size="sm"
          icon="i-lucide-plus"
          label="登记资产"
          @click="openNew"
        />
      </div>

      <div
        class="flex flex-wrap items-center gap-4 px-4 py-3 mb-4 rounded-xl bg-n-alpha-1"
      >
        <div class="flex items-baseline gap-2">
          <span class="text-sm text-n-slate-11">资产原值合计</span>
          <b class="text-xl text-n-slate-12">{{ cny(totalAmount) }}</b>
          <span class="text-xs text-n-slate-10">{{ rows.length }} 项</span>
        </div>
        <div class="flex flex-wrap items-center gap-3 text-xs text-n-slate-11">
          <span v-for="s in byStatus" :key="s.label">
            {{ s.label }}
            <b class="text-n-slate-12">{{ s.count }}</b>
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
              <th class="px-4 py-3 font-medium text-left">资产</th>
              <th class="px-4 py-3 font-medium text-left">编号</th>
              <th class="px-4 py-3 font-medium text-left">类别</th>
              <th class="px-4 py-3 font-medium text-left">部门</th>
              <th class="px-4 py-3 font-medium text-left">使用人</th>
              <th class="px-4 py-3 font-medium text-left">存放位置</th>
              <th class="px-4 py-3 font-medium text-left">购入日期</th>
              <th class="px-4 py-3 font-medium text-right">原值</th>
              <th class="px-4 py-3 font-medium text-left">状态</th>
              <th class="px-4 py-3 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="a in rows"
              :key="a.id"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-4 py-3 text-n-slate-12">
                {{ a.name }}
                <button
                  v-for="f in a.files"
                  :key="f.id"
                  type="button"
                  class="ml-1 text-xs text-n-iris-11 hover:underline"
                  @click="previewFile = f"
                >
                  附件
                </button>
              </td>
              <td class="px-4 py-3 text-n-slate-11">{{ a.code }}</td>
              <td class="px-4 py-3 text-n-slate-11">{{ a.category }}</td>
              <td class="px-4 py-3 text-n-slate-11">{{ a.departmentName }}</td>
              <td class="px-4 py-3 text-n-slate-11">{{ a.holderName }}</td>
              <td class="px-4 py-3 text-n-slate-11">{{ a.location }}</td>
              <td class="px-4 py-3 whitespace-nowrap text-n-slate-11">
                {{ a.purchasedOn }}
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-n-slate-12">
                {{ cny(a.amount) }}
              </td>
              <td class="px-4 py-3">
                <span
                  class="px-2 py-0.5 text-xs rounded-full"
                  :class="
                    a.status === 'SCRAPPED'
                      ? 'bg-n-ruby-3 text-n-ruby-11'
                      : a.status === 'IN_USE'
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-alpha-2 text-n-slate-11'
                  "
                >
                  {{ a.statusLabel }}
                </span>
              </td>
              <td class="px-4 py-3 text-right whitespace-nowrap">
                <template v-if="canEditDept(a.departmentId)">
                  <Button
                    variant="ghost"
                    color="slate"
                    size="xs"
                    icon="i-lucide-pencil"
                    @click="openEdit(a)"
                  />
                  <Button
                    variant="ghost"
                    color="ruby"
                    size="xs"
                    icon="i-lucide-trash-2"
                    @click="remove(a)"
                  />
                </template>
                <span v-else class="text-xs text-n-slate-10">只读</span>
              </td>
            </tr>
            <tr v-if="!rows.length">
              <td colspan="10" class="px-4 py-12 text-center text-n-slate-10">
                还没有登记资产{{
                  canCreate ? '，点右上角「登记资产」开始。' : '。'
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <AttachmentPreview :file="previewFile" @close="previewFile = null" />

    <!-- 登记弹窗 -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40"
      @click.self="showForm = false"
    >
      <div
        class="w-full max-w-[95vw] sm:max-w-2xl p-4 sm:p-6 overflow-y-auto max-h-[90vh] rounded-2xl bg-n-solid-1 shadow-xl [.theme-classic_&]:sm:!p-8"
      >
        <h2 class="mb-4 text-lg font-semibold text-n-slate-12">
          {{ isEdit ? '编辑资产' : '登记资产' }}
        </h2>

        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3">
          <label class="flex flex-col col-span-2 gap-1">
            <span class="text-xs text-n-slate-11">资产名称</span>
            <input
              v-model="form.name"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">编号（选填）</span>
            <input
              v-model="form.code"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">部门</span>
            <SelectCard
              v-model="form.departmentId"
              :options="departmentOptions"
              block
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">类别</span>
            <SelectCard
              v-model="form.category"
              :options="CATEGORIES.map(c => ({ value: c, label: c }))"
              block
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">状态</span>
            <SelectCard v-model="form.status" :options="STATUSES" block />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">购入日期</span>
            <DatePicker v-model="form.purchasedOn" block />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">原值 (CNY)</span>
            <input
              v-model.number="form.amount"
              type="number"
              min="0"
              step="0.01"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">使用人</span>
            <SelectCard
              v-model="form.holderId"
              :options="holderOptions"
              block
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">存放位置</span>
            <input
              v-model="form.location"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col col-span-2 gap-1 sm:col-span-3">
            <span class="text-xs text-n-slate-11">备注（选填）</span>
            <input
              v-model="form.remark"
              type="text"
              class="w-full h-9 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </div>

        <div class="flex flex-col gap-1 mt-4">
          <span class="text-xs text-n-slate-11">照片 / 发票（选填）</span>
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
            添加附件
          </button>
          <div
            v-for="(f, i) in pendingFiles"
            :key="i"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span class="truncate">{{ f.name }}</span>
            <button type="button" class="text-n-ruby-11" @click="removeFile(i)">
              移除
            </button>
          </div>
        </div>

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
