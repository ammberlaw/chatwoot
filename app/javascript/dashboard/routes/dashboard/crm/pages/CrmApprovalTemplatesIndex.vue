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
  condTitle: '条件分支',
  condHint:
    '按分支从上往下判断，命中第一个「条件全部满足」的分支就走它的审批人；都不满足走「其他情况」。例：请假天数 > 2 → 总经理。',
  branch: '分支',
  defaultBranch: '其他情况（默认）',
  addBranch: '加分支',
  addCond: '加条件',
  branchApprovers: '该情况审批人',
  stepType: '审批人',
  deptLeader: '申请人部门主管',
  specificUser: '指定成员',
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

// 条件运算符：数值型全量，选择/文本仅等于/不等于。
const OPERATORS = [
  { value: 'lte', label: '≤' },
  { value: 'lt', label: '<' },
  { value: 'gte', label: '≥' },
  { value: 'gt', label: '>' },
  { value: 'eq', label: '=' },
  { value: 'neq', label: '≠' },
];
const ENUM_OPS = ['eq', 'neq'];
const editingId = ref(null);
let seq = 0;
const nextSeq = () => {
  seq += 1;
  return seq;
};
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

const fetchTemplates = async () => {
  const { data } = await TemplatesAPI.get();
  templates.value = data.payload || [];
};

// 后端 flow → 编辑器内部结构（条件节点带 branches；普通步骤带 userId）。
const parseApprover = s => ({
  seq: nextSeq(),
  type: s.type || 'dept_leader',
  userId: s.user_id ? String(s.user_id) : '',
});
const parseStep = s => {
  if (s.type !== 'condition') return parseApprover(s);
  return {
    seq: nextSeq(),
    type: 'condition',
    branches: (s.branches || []).map(b => ({
      seq: nextSeq(),
      conditions: (b.conditions || []).map(c => ({
        seq: nextSeq(),
        var: c.var,
        op: c.op,
        value: c.value != null ? String(c.value) : '',
      })),
      flow: (b.flow || []).map(parseApprover),
    })),
  };
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
  dialogRef.value?.open();
};

const addField = () => {
  seq += 1;
  form.value.fields.push({
    seq,
    key: `field_${seq}`,
    label: '',
    type: 'text',
    required: false,
    optionsText: '',
  });
};
const removeField = i => form.value.fields.splice(i, 1);

// 一个审批人步骤（部门主管 / 指定成员）。
const blankApprover = () => ({
  seq: nextSeq(),
  type: 'dept_leader',
  userId: '',
});

// 可用作条件判断的变量：请假天数（联动请假时）/ 申请人部门 / 数字·金额·下拉字段。
const conditionVars = computed(() => {
  const list = [];
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
const varMeta = v =>
  conditionVars.value.find(x => x.value === v) || { kind: 'number' };
const opsForVar = v =>
  varMeta(v).kind === 'number'
    ? OPERATORS
    : OPERATORS.filter(o => ENUM_OPS.includes(o.value));

const blankCondRow = () => ({
  seq: nextSeq(),
  var: conditionVars.value[0]?.value || 'leave_days',
  op: 'lte',
  value: '',
});
const blankBranch = () => ({
  seq: nextSeq(),
  conditions: [blankCondRow()],
  flow: [blankApprover()],
});
const isDefaultBranch = b => (b.conditions || []).length === 0;

const addStep = () => form.value.flow.push(blankApprover());
// 条件节点：初始给一个「有条件」分支 + 一个「其他情况」兜底分支。
const addCondition = () =>
  form.value.flow.push({
    seq: nextSeq(),
    type: 'condition',
    branches: [
      blankBranch(),
      { seq: nextSeq(), conditions: [], flow: [blankApprover()] },
    ],
  });
const removeStep = i => form.value.flow.splice(i, 1);

// 新分支插到「默认分支」前面，保证兜底始终在最后。
const addBranch = step => {
  const idx = step.branches.findIndex(isDefaultBranch);
  const nb = blankBranch();
  if (idx >= 0) step.branches.splice(idx, 0, nb);
  else step.branches.push(nb);
};
const removeBranch = (step, bi) => step.branches.splice(bi, 1);
const addCondRow = branch => branch.conditions.push(blankCondRow());
const removeCondRow = (branch, ci) => branch.conditions.splice(ci, 1);
const addBranchStep = branch => branch.flow.push(blankApprover());
const removeBranchStep = (branch, si) => branch.flow.splice(si, 1);
// 变量类型变了（如从天数换成下拉），运算符若不适用则回落到「=」。
const onVarChange = cond => {
  if (!opsForVar(cond.var).some(o => o.value === cond.op)) cond.op = 'eq';
  cond.value = '';
};

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
const attendanceKindOptions = computed(() => [
  { value: '', label: '不联动' },
  {
    value: 'leave',
    label: '请假单（按日期区间标记请假；单日+时段字段填上午/下午=半天假）',
  },
  { value: 'reclock', label: '补卡申请（该日补为正常）' },
  { value: 'trip', label: '出差单（按日期区间标记外勤）' },
]);
const ccCandidateOptions = computed(() => [
  { value: '', label: L.ccAdd },
  ...ccCandidates.value.map(a => ({ value: String(a.id), label: a.name })),
]);

// flow 序列化：普通步骤 {type,user_id}；条件节点 {type:'condition',branches:[{conditions,flow}]}。
const serializeApprover = s => ({
  type: s.type,
  user_id: s.type === 'user' && s.userId ? Number(s.userId) : null,
});
const serializeCondValue = c => {
  const kind = varMeta(c.var).kind;
  return kind === 'number' || kind === 'dept' ? Number(c.value) : c.value;
};
const serializeStep = s => {
  if (s.type !== 'condition') return serializeApprover(s);
  return {
    type: 'condition',
    branches: (s.branches || []).map(b => ({
      conditions: (b.conditions || []).map(c => ({
        var: c.var,
        op: c.op,
        value: serializeCondValue(c),
      })),
      flow: (b.flow || []).map(serializeApprover),
    })),
  };
};

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
    flow: form.value.flow.map(serializeStep),
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
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
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

    <div v-else class="flex-1 px-4 py-3 sm:px-6 sm:py-4">
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
      @confirm="save"
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
          <div class="flex flex-col gap-2">
            <template v-for="(s, i) in form.flow" :key="s.seq">
              <!-- 条件分支节点 -->
              <div
                v-if="s.type === 'condition'"
                class="p-2 border rounded-lg border-n-iris-6 bg-n-iris-2/40"
              >
                <div class="flex items-center gap-2 mb-1">
                  <span
                    class="flex items-center justify-center rounded-full size-6 bg-n-iris-4 text-n-iris-11 text-[11px]"
                  >
                    {{ i + 1 }}
                  </span>
                  <span class="text-xs font-medium text-n-iris-11">
                    {{ L.condTitle }}
                  </span>
                  <span class="flex-1" />
                  <button
                    class="text-xs text-n-iris-11 hover:underline"
                    @click="addBranch(s)"
                  >
                    + {{ L.addBranch }}
                  </button>
                  <button
                    class="text-n-slate-10 hover:text-n-ruby-11"
                    @click="removeStep(i)"
                  >
                    <Icon icon="i-lucide-x" class="size-4" />
                  </button>
                </div>
                <p class="mb-1.5 text-[11px] text-n-slate-10">
                  {{ L.condHint }}
                </p>
                <div class="flex flex-col gap-1.5">
                  <div
                    v-for="(b, bi) in s.branches"
                    :key="b.seq"
                    class="p-2 border rounded-md bg-n-solid-1 border-n-weak"
                  >
                    <div class="flex items-center gap-2 mb-1">
                      <span class="text-[11px] font-medium text-n-slate-11">
                        {{
                          isDefaultBranch(b)
                            ? L.defaultBranch
                            : `${L.branch} ${bi + 1}`
                        }}
                      </span>
                      <span class="flex-1" />
                      <button
                        v-if="s.branches.length > 1"
                        class="text-n-slate-10 hover:text-n-ruby-11"
                        @click="removeBranch(s, bi)"
                      >
                        <Icon icon="i-lucide-trash-2" class="size-3.5" />
                      </button>
                    </div>
                    <!-- 条件行（默认分支无条件） -->
                    <div
                      v-if="!isDefaultBranch(b)"
                      class="flex flex-col gap-1 mb-1.5"
                    >
                      <div
                        class="flex items-center gap-1 text-[11px] text-n-slate-10"
                      >
                        <span class="w-5 shrink-0" />
                        <span class="flex-1">条件字段</span>
                        <span class="w-14 shrink-0 text-center">比较</span>
                        <span class="flex-1">值</span>
                        <span class="w-5 shrink-0" />
                      </div>
                      <div
                        v-for="(c, ci) in b.conditions"
                        :key="c.seq"
                        class="flex items-center gap-1"
                      >
                        <span
                          class="w-5 shrink-0 text-[11px] text-center text-n-slate-9"
                        >
                          {{ ci > 0 ? '且' : '' }}
                        </span>
                        <select
                          v-model="c.var"
                          class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                          @change="onVarChange(c)"
                        >
                          <option
                            v-for="v in conditionVars"
                            :key="v.value"
                            :value="v.value"
                          >
                            {{ v.label }}
                          </option>
                        </select>
                        <select
                          v-model="c.op"
                          class="w-14 shrink-0 h-8 px-1 text-xs text-center border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                        >
                          <option
                            v-for="o in opsForVar(c.var)"
                            :key="o.value"
                            :value="o.value"
                          >
                            {{ o.label }}
                          </option>
                        </select>
                        <select
                          v-if="varMeta(c.var).kind === 'dept'"
                          v-model="c.value"
                          class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                        >
                          <option value="">选择部门…</option>
                          <option
                            v-for="d in departments"
                            :key="d.id"
                            :value="String(d.id)"
                          >
                            {{ d.name }}
                          </option>
                        </select>
                        <select
                          v-else-if="varMeta(c.var).kind === 'enum'"
                          v-model="c.value"
                          class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                        >
                          <option value="">选择…</option>
                          <option
                            v-for="opt in varMeta(c.var).options || []"
                            :key="opt"
                            :value="opt"
                          >
                            {{ opt }}
                          </option>
                        </select>
                        <input
                          v-else
                          v-model="c.value"
                          type="number"
                          placeholder="填数值"
                          class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                        />
                        <button
                          class="w-5 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                          :class="b.conditions.length > 1 ? '' : 'invisible'"
                          @click="removeCondRow(b, ci)"
                        >
                          <Icon icon="i-lucide-x" class="size-3.5" />
                        </button>
                      </div>
                      <button
                        class="self-start text-[11px] text-n-iris-11 hover:underline"
                        @click="addCondRow(b)"
                      >
                        + {{ L.addCond }}
                      </button>
                    </div>
                    <!-- 该分支的审批人 -->
                    <div class="pl-2 border-l-2 border-n-iris-5">
                      <div class="text-[11px] text-n-slate-10 mb-1">
                        {{ L.branchApprovers }}
                      </div>
                      <div class="flex flex-col gap-1">
                        <div
                          v-for="(bs, si) in b.flow"
                          :key="bs.seq"
                          class="flex items-center gap-1.5"
                        >
                          <span
                            class="flex items-center justify-center rounded-full size-5 bg-n-iris-3 text-n-iris-11 text-[10px]"
                          >
                            {{ si + 1 }}
                          </span>
                          <select
                            v-model="bs.type"
                            class="h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                          >
                            <option value="dept_leader">
                              {{ L.deptLeader }}
                            </option>
                            <option value="user">{{ L.specificUser }}</option>
                          </select>
                          <select
                            v-if="bs.type === 'user'"
                            v-model="bs.userId"
                            class="flex-1 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                          >
                            <option value="">选择成员…</option>
                            <option
                              v-for="a in agents"
                              :key="a.id"
                              :value="String(a.id)"
                            >
                              {{ a.name }}
                            </option>
                          </select>
                          <span class="flex-1" />
                          <button
                            v-if="b.flow.length > 1"
                            class="text-n-slate-10 hover:text-n-ruby-11"
                            @click="removeBranchStep(b, si)"
                          >
                            <Icon icon="i-lucide-x" class="size-3.5" />
                          </button>
                        </div>
                        <button
                          class="self-start text-[11px] text-n-iris-11 hover:underline"
                          @click="addBranchStep(b)"
                        >
                          + {{ L.addStep }}
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <!-- 普通审批人步骤 -->
              <div
                v-else
                class="flex items-center gap-2 p-2 border rounded-lg border-n-weak"
              >
                <span
                  class="flex items-center justify-center rounded-full size-6 bg-n-iris-4 text-n-iris-11 text-[11px]"
                >
                  {{ i + 1 }}
                </span>
                <select
                  v-model="s.type"
                  class="h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                >
                  <option value="dept_leader">{{ L.deptLeader }}</option>
                  <option value="user">{{ L.specificUser }}</option>
                </select>
                <select
                  v-if="s.type === 'user'"
                  v-model="s.userId"
                  class="flex-1 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                >
                  <option value="">{{ '选择成员…' }}</option>
                  <option v-for="a in agents" :key="a.id" :value="String(a.id)">
                    {{ a.name }}
                  </option>
                </select>
                <span class="flex-1" />
                <button
                  class="text-n-slate-10 hover:text-n-ruby-11"
                  @click="removeStep(i)"
                >
                  <Icon icon="i-lucide-x" class="size-4" />
                </button>
              </div>
            </template>
          </div>
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
