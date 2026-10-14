<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import TemplatesAPI from 'dashboard/api/oa/approvalTemplates';
import AgentAPI from 'dashboard/api/agents';
import DepartmentsAPI from 'dashboard/api/org/departments';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import { isClassicTheme } from 'dashboard/components-next/CRM/charts/chartColors';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
import CrmApprovalFlowEditor from 'dashboard/components-next/CRM/CrmApprovalFlowEditor.vue';
import {
  nextSeq,
  parseStep,
  serializeStep,
  blankApprover,
  blankCondition,
} from 'dashboard/helper/oaApprovalFlow';
// 经典灰专属：模板卡图标底改金黄，避免被压灰像停用。切主题需刷新。
const isClassic = ref(isClassicTheme());

// 维护权：管理员或人事部门成员（与后端 oa_template_maintainer? 一致）；其他人整页不可见。
const currentUser = useMapGetter('getCurrentUser');
const canMaintain = computed(
  () => currentUser.value?.oa_template_maintainer === true
);

const L = {
  header: '审批模板',
  hint: '定义审批类型的表单字段与审批流程，供全员发起审批时选用。',
  new: '新建模板',
  empty: '还没有模板，点右上「新建模板」',
  edit: '编辑模板',
  create: '新建审批模板',
  name: '模板名称',
  desc: '说明',
  icon: '图标',
  fields: '表单字段',
  addField: '添加字段',
  fieldLabel: '字段名',
  fieldType: '类型',
  required: '必填',
  options: '选项（逗号分隔）',
  flow: '审批流程',
  addStep: '添加审批人',
  addCondition: '添加条件分支',
  ccLabel: '抄送人',
  ccHint: '抄送人不参与审批，可在审批中心「抄送我的」里看到该单据。',
  ccAdd: '添加抄送人…',
  remove: '删除',
  save: '保存',
  deleteConfirm: '删除该模板？已发起的审批单不受影响。',
  saved: '已保存',
  deleted: '已删除',
  error: '操作失败',
  needName: '请填写模板名称',
  noAccess: '仅超级管理员、管理员与人事部门成员可维护审批模板',
  fieldCount: n => `${n} 个字段`,
  stepCount: n => `${n} 级审批`,
};

const FIELD_TYPES = [
  { value: 'text', label: '单行文本' },
  { value: 'textarea', label: '多行文本' },
  { value: 'number', label: '数字' },
  { value: 'amount', label: '金额' },
  { value: 'date', label: '日期' },
  { value: 'datetime', label: '日期时间' },
  { value: 'select', label: '下拉选择' },
];
const ICONS = [
  'i-lucide-plane',
  'i-lucide-receipt',
  'i-lucide-file-check',
  'i-lucide-briefcase',
  'i-lucide-shopping-cart',
  'i-lucide-stamp',
  'i-lucide-clock',
  'i-lucide-banknote',
];

const templates = ref([]);
const agents = ref([]);
const departments = ref([]);
const dialogRef = ref(null);

const editingId = ref(null);
const form = ref({
  name: '',
  description: '',
  icon: ICONS[2],
  active: true,
  attendanceKind: '',
  erpExpense: false,
  fields: [],
  flow: [],
  ccUserIds: [],
});
const { isDirty, markPristine } = useDirtyGuard(() => form.value);

const fetchTemplates = async () => {
  const { data } = await TemplatesAPI.get();
  templates.value = data.payload || [];
};

const resetForm = () => {
  form.value = {
    name: '',
    description: '',
    icon: ICONS[2],
    active: true,
    attendanceKind: '',
    erpExpense: false,
    fields: [],
    flow: [],
    ccUserIds: [],
  };
};

const openCreate = () => {
  editingId.value = null;
  resetForm();
  markPristine();
  dialogRef.value?.open();
};

const openEdit = tpl => {
  editingId.value = tpl.id;
  form.value = {
    name: tpl.name || '',
    description: tpl.description || '',
    icon: tpl.icon || ICONS[2],
    active: tpl.active !== false,
    attendanceKind: tpl.attendance_kind || '',
    erpExpense: !!tpl.erp_expense,
    fields: (tpl.form_fields || []).map(f => ({
      seq: nextSeq(),
      key: f.key,
      label: f.label,
      type: f.type || 'text',
      required: !!f.required,
      optionsText: (f.options || []).join(','),
    })),
    flow: (tpl.flow || []).map(parseStep),
    ccUserIds: (tpl.cc_user_ids || []).map(String),
  };
  markPristine();
  dialogRef.value?.open();
};

const addField = () => {
  const id = nextSeq();
  form.value.fields.push({
    seq: id,
    key: `field_${id}`,
    label: '',
    type: 'text',
    required: false,
    optionsText: '',
  });
};
const removeField = i => form.value.fields.splice(i, 1);

// 可用作条件判断的变量：发起人属于（部门+成员多选）/ 请假天数（联动请假时）/
// 申请人部门（单选等于，老模板还在用）/ 数字·金额·下拉字段。
const conditionVars = computed(() => {
  const list = [{ value: 'applicant', label: '发起人', kind: 'applicant' }];
  const hasDate = form.value.fields.some(f => f.type === 'date');
  if (form.value.attendanceKind === 'leave' || hasDate) {
    list.push({
      value: 'leave_days',
      label:
        form.value.attendanceKind === 'leave' ? '请假天数' : '天数(日期区间)',
      kind: 'number',
    });
  }
  list.push({ value: 'department', label: '申请人部门', kind: 'dept' });
  form.value.fields.forEach(f => {
    const label = (f.label || '').trim() || f.key;
    if (['number', 'amount'].includes(f.type)) {
      list.push({ value: `field:${f.key}`, label, kind: 'number' });
    } else if (f.type === 'select') {
      list.push({
        value: `field:${f.key}`,
        label,
        kind: 'enum',
        options: f.optionsText
          .split(',')
          .map(o => o.trim())
          .filter(Boolean),
      });
    }
  });
  return list;
});
// 顶层的「添加审批人 / 添加条件分支」在标题行上；分支内部的由编辑器组件自带。
const addStep = () => form.value.flow.push(blankApprover());
const addCondition = () =>
  form.value.flow.push(blankCondition(conditionVars.value));

// 抄送人：多选成员（不参与审批，仅知会）。
const toggleCc = id => {
  const s = String(id);
  const idx = form.value.ccUserIds.indexOf(s);
  if (idx >= 0) form.value.ccUserIds.splice(idx, 1);
  else form.value.ccUserIds.push(s);
};
const ccName = id =>
  agents.value.find(a => String(a.id) === String(id))?.name || id;
const ccCandidates = computed(() =>
  agents.value.filter(a => !form.value.ccUserIds.includes(String(a.id)))
);

// 原生 select → 紫玻璃 SelectCard 选项（保留原首个空值项）。
// 请假模板里还留着纯「日期」字段：只能选到天，半天假/两小时假填不出来。
const hasPlainDateField = computed(() =>
  (form.value.fields || []).some(f => f.type === 'date')
);

const attendanceKindOptions = computed(() => [
  { value: '', label: '不联动' },
  {
    value: 'leave',
    label: '请假单（按日期区间标记请假；单日且时长不超过半个工作日=半天假）',
  },
  { value: 'reclock', label: '补卡申请（该日补为正常）' },
  { value: 'trip', label: '出差单（按日期区间标记外勤）' },
]);
const ccCandidateOptions = computed(() => [
  { value: '', label: L.ccAdd },
  ...ccCandidates.value.map(a => ({ value: String(a.id), label: a.name })),
]);

const save = async () => {
  if (!form.value.name.trim()) {
    useAlert(L.needName);
    return;
  }
  const payload = {
    name: form.value.name.trim(),
    description: form.value.description.trim() || null,
    icon: form.value.icon,
    active: form.value.active,
    attendance_kind: form.value.attendanceKind || null,
    erp_expense: form.value.erpExpense,
    form_fields: form.value.fields.map(f => ({
      key: f.key,
      label: f.label.trim() || f.key,
      type: f.type,
      required: f.required,
      options:
        f.type === 'select'
          ? f.optionsText
              .split(',')
              .map(o => o.trim())
              .filter(Boolean)
          : [],
    })),
    flow: form.value.flow.map(s => serializeStep(conditionVars.value, s)),
    cc_user_ids: form.value.ccUserIds.map(Number),
  };
  try {
    if (editingId.value) {
      await TemplatesAPI.modify(editingId.value, payload);
    } else {
      await TemplatesAPI.save(payload);
    }
    dialogRef.value?.close();
    fetchTemplates();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeTemplate = async () => {
  // eslint-disable-next-line no-alert
  if (!editingId.value || !window.confirm(L.deleteConfirm)) return;
  try {
    await TemplatesAPI.remove(editingId.value);
    dialogRef.value?.close();
    fetchTemplates();
    useAlert(L.deleted);
  } catch {
    useAlert(L.error);
  }
};

onMounted(async () => {
  fetchTemplates();
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
  try {
    const { data } = await DepartmentsAPI.get();
    departments.value = data.payload || data || [];
  } catch {
    departments.value = [];
  }
});
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        v-if="canMaintain"
        :label="L.new"
        icon="i-lucide-plus"
        color="iris"
        class="shrink-0"
        @click="openCreate"
      />
    </div>

    <!-- 非管理员/人事部门成员：整页不可见（直链兜底） -->
    <div
      v-if="!canMaintain"
      class="flex flex-col items-center justify-center flex-1 gap-3 text-center"
    >
      <span
        class="grid rounded-full size-12 place-items-center bg-n-slate-3 text-n-slate-10"
      >
        <Icon icon="i-lucide-lock" class="size-5" />
      </span>
      <p class="text-sm text-n-slate-11">{{ L.noAccess }}</p>
    </div>

    <div v-else class="flex-1 px-4 py-3 sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <div
        v-if="!templates.length"
        class="p-8 text-sm text-center text-n-slate-10"
      >
        {{ L.empty }}
      </div>
      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          class="flex items-center gap-3 p-4 text-left transition-shadow border rounded-2xl border-n-weak bg-n-solid-1 hover:shadow-sm hover:border-n-iris-7 disabled:cursor-default"
          @click="openEdit(tpl)"
        >
          <div
            class="flex items-center justify-center flex-shrink-0 rounded-lg size-10"
            :class="
              isClassic
                ? 'bg-[#fdf1c6] text-[#a97e0c]'
                : 'bg-n-iris-4 text-n-iris-11'
            "
          >
            <Icon :icon="tpl.icon || 'i-lucide-file-check'" class="size-5" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ tpl.name }}
              </span>
              <span
                v-if="!tpl.active"
                class="px-1.5 rounded text-[10px] bg-n-slate-3 text-n-slate-10"
              >
                {{ '已停用' }}
              </span>
            </div>
            <div class="text-xs truncate text-n-slate-10">
              {{
                `${L.fieldCount((tpl.form_fields || []).length)} · ${L.stepCount((tpl.flow || []).length)}`
              }}
            </div>
          </div>
        </button>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      width="2xl"
      overflow-y-auto
      :title="editingId ? L.edit : L.create"
      :confirm-button-label="L.save"
      confirm-button-color="iris"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="save"
      @close="markPristine"
      @save="save"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <Input v-model="form.name" :label="L.name" autofocus />
          <Input v-model="form.description" :label="L.desc" />
        </div>

        <!-- 考勤联动：请假/补卡模板审批通过后自动写入考勤 -->
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">考勤联动</span>
          <SelectCard
            v-model="form.attendanceKind"
            :options="attendanceKindOptions"
            block
          />
          <span v-if="form.attendanceKind" class="text-xs text-n-slate-10">
            表单需包含日期字段：请假取最早/最晚两个日期为区间，补卡取第一个日期；整单审批通过后自动写入考勤（留痕）。
          </span>
          <!-- 请假只配了「日期」就只能选到天，半天假、下午请两小时都填不出来。
               用户点名：请假还是只有日期，没有像外出申请一样能选具体时间。 -->
          <span
            v-if="form.attendanceKind === 'leave' && hasPlainDateField"
            class="text-xs text-n-amber-11"
          >
            下面的日期字段现在是「日期」，申请人只能选到哪一天。要像外出申请那样精确到几点，
            把它改成「日期时间」——半天假、请两小时才填得出来。
          </span>
        </label>

        <!-- 财务联动：标记后，审批通过的单会进 ERP「费用报销」待打款列表 -->
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">财务联动</span>
          <span
            class="inline-flex items-center gap-2 text-sm cursor-pointer text-n-slate-11"
          >
            <input
              v-model="form.erpExpense"
              type="checkbox"
              class="accent-n-iris-9"
            />
            这是费用报销单（审批通过后进财务「待打款」列表）
          </span>
          <span v-if="form.erpExpense" class="text-xs text-n-slate-10">
            表单需包含金额字段（type=金额）；财务打款后自动记出纳日记账与待过账凭证，挂了订单的进订单成本。
          </span>
        </label>

        <!-- 图标 -->
        <div>
          <label class="block mb-1 text-heading-3 text-n-slate-12">
            {{ L.icon }}
          </label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="ic in ICONS"
              :key="ic"
              class="flex items-center justify-center border rounded-lg size-9"
              :class="
                form.icon === ic
                  ? 'border-n-iris-9 bg-n-iris-3 text-n-iris-11'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="form.icon = ic"
            >
              <Icon :icon="ic" class="size-4" />
            </button>
          </div>
        </div>

        <!-- 表单字段 -->
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="text-heading-3 text-n-slate-12">{{ L.fields }}</label>
            <button
              class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
              @click="addField"
            >
              <Icon icon="i-lucide-plus" class="size-3.5" />
              {{ L.addField }}
            </button>
          </div>
          <div class="flex flex-col gap-2">
            <div
              v-for="(f, i) in form.fields"
              :key="f.seq"
              class="flex flex-wrap items-center gap-2 p-2 border rounded-lg border-n-weak"
            >
              <input
                v-model="f.label"
                :placeholder="L.fieldLabel"
                class="flex-1 min-w-[100px] h-8 px-2 text-sm border rounded reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
              />
              <select
                v-model="f.type"
                class="h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
              >
                <option
                  v-for="t in FIELD_TYPES"
                  :key="t.value"
                  :value="t.value"
                >
                  {{ t.label }}
                </option>
              </select>
              <input
                v-if="f.type === 'select'"
                v-model="f.optionsText"
                :placeholder="L.options"
                class="flex-1 min-w-[120px] h-8 px-2 text-sm border rounded reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
              />
              <label
                class="inline-flex items-center gap-1 text-xs cursor-pointer text-n-slate-11"
              >
                <input
                  v-model="f.required"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
                {{ L.required }}
              </label>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeField(i)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- 审批流程 -->
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="text-heading-3 text-n-slate-12">{{ L.flow }}</label>
            <div class="flex items-center gap-3">
              <button
                class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
                @click="addStep"
              >
                <Icon icon="i-lucide-plus" class="size-3.5" />
                {{ L.addStep }}
              </button>
              <button
                class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
                @click="addCondition"
              >
                <Icon icon="i-lucide-git-branch" class="size-3.5" />
                {{ L.addCondition }}
              </button>
            </div>
          </div>
          <CrmApprovalFlowEditor
            v-model="form.flow"
            :vars="conditionVars"
            :agents="agents"
            :departments="departments"
          />
        </div>

        <!-- 抄送人 -->
        <div>
          <label class="text-heading-3 text-n-slate-12">{{ L.ccLabel }}</label>
          <p class="mt-0.5 mb-1.5 text-xs text-n-slate-10">{{ L.ccHint }}</p>
          <div v-if="form.ccUserIds.length" class="flex flex-wrap gap-1.5 mb-2">
            <span
              v-for="id in form.ccUserIds"
              :key="id"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
            >
              {{ ccName(id) }}
              <button class="hover:text-n-ruby-11" @click="toggleCc(id)">
                <Icon icon="i-lucide-x" class="size-3" />
              </button>
            </span>
          </div>
          <SelectCard
            model-value=""
            :options="ccCandidateOptions"
            :placeholder="L.ccAdd"
            block
            @update:model-value="val => val && toggleCc(val)"
          />
        </div>

        <button
          v-if="editingId"
          class="inline-flex items-center self-start gap-1 text-xs text-n-ruby-11 hover:underline"
          @click="removeTemplate"
        >
          <Icon icon="i-lucide-trash-2" class="size-3.5" />
          {{ L.remove }}
        </button>
      </div>
    </Dialog>
  </div>
</template>
