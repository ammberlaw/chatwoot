<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import TemplatesAPI from 'dashboard/api/oa/approvalTemplates';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import MembershipsAPI from 'dashboard/api/org/memberships';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const L = {
  header: '审批中心',
  start: '发起审批',
  tabTodo: '待我审批',
  tabMine: '我发起的',
  empty: '暂无审批单',
  selectHint: '选择左侧审批单查看详情',
  pickTemplate: '选择审批类型',
  submit: '提交',
  approve: '同意',
  reject: '驳回',
  cancel: '撤回',
  commentPlaceholder: '审批意见（可选）',
  applicant: '申请人',
  flow: '审批流程',
  required: '请填写必填项',
  submitted: '已提交',
  done: '已处理',
  canceled: '已撤回',
  error: '操作失败',
  current: '审批中',
  dept: '所在部门',
  deptPlaceholder: '请选择部门',
  upper: '大写：',
  attachments: '附件',
  addAttachment: '添加附件',
  flowPreview: '审批流程',
  deptLeader: '部门主管',
  unresolved: '（未设置负责人）',
  place: '请输入',
};

// 数字转人民币大写
const amountToWords = value => {
  const num = Number(value);
  if (!value || Number.isNaN(num) || num < 0) return '';
  const digits = '零壹贰叁肆伍陆柒捌玖';
  const bigUnit = ['', '万', '亿', '兆'];
  const unit = ['', '拾', '佰', '仟'];
  const fixed = num.toFixed(2);
  const [intPart, decPart] = fixed.split('.');
  let intText = '';
  if (Number(intPart) === 0) {
    intText = '零';
  } else {
    const groups = [];
    let rest = intPart;
    while (rest.length) {
      groups.unshift(rest.slice(-4));
      rest = rest.slice(0, -4);
    }
    groups.forEach((group, gi) => {
      let seg = '';
      let zero = false;
      const padded = group.padStart(4, '0');
      for (let i = 0; i < 4; i += 1) {
        const d = Number(padded[i]);
        if (d === 0) {
          zero = true;
        } else {
          if (zero) seg += '零';
          zero = false;
          seg += digits[d] + unit[3 - i];
        }
      }
      if (seg) intText += seg + bigUnit[groups.length - 1 - gi];
    });
  }
  const jiao = Number(decPart[0]);
  const fen = Number(decPart[1]);
  let decText = '';
  if (jiao === 0 && fen === 0) {
    decText = '整';
  } else {
    decText =
      (jiao ? `${digits[jiao]}角` : '') + (fen ? `${digits[fen]}分` : '');
    if (jiao === 0 && fen) decText = `零${decText}`;
  }
  return `${intText}元${decText}`;
};

const STATUS_META = {
  pending: { label: '审批中', class: 'bg-n-iris-3 text-n-iris-11' },
  approved: { label: '已通过', class: 'bg-n-teal-3 text-n-teal-11' },
  rejected: { label: '已驳回', class: 'bg-n-ruby-3 text-n-ruby-11' },
  canceled: { label: '已撤回', class: 'bg-n-slate-3 text-n-slate-11' },
};
const STEP_META = {
  pending: { icon: 'i-lucide-clock', class: 'text-n-iris-11' },
  approved: { icon: 'i-lucide-check', class: 'text-n-teal-11' },
  rejected: { icon: 'i-lucide-x', class: 'text-n-ruby-11' },
  skipped: { icon: 'i-lucide-minus', class: 'text-n-slate-10' },
};

const TABS = [
  { key: 'todo', label: L.tabTodo },
  { key: 'mine', label: L.tabMine },
];

const activeTab = ref('todo');
const requests = ref([]);
const counts = ref({ todo: 0, mine: 0 });
const selected = ref(null);
const comment = ref('');

const templates = ref([]);
const pickerRef = ref(null);
const formRef = ref(null);
const activeTemplate = ref(null);
const formValues = ref({});
const myDepartments = ref([]);
const agents = ref([]);
const selectedDeptId = ref('');
const attachments = ref([]);
const fileInputRef = ref(null);

const templateFlow = computed(
  () => activeTemplate.value?.flow || activeTemplate.value?.flow || []
);
const needsDept = computed(() =>
  templateFlow.value.some(s => s.type === 'dept_leader')
);
const pickedDept = computed(() =>
  myDepartments.value.find(
    d => String(d.department_id) === selectedDeptId.value
  )
);

// 提交前预览审批链：部门主管→所选部门负责人；指定成员→该成员。
const flowPreview = computed(() =>
  templateFlow.value.map(step => {
    if (step.type === 'user') {
      const a = agents.value.find(x => x.id === step.user_id);
      return a?.name || L.unresolved;
    }
    return pickedDept.value?.department_leader_name || L.unresolved;
  })
);

const fmtDateTime = v =>
  v ? new Date(v).toLocaleString('zh-CN', { hour12: false }) : '';
const initial = n => (n || '?').trim().charAt(0).toUpperCase();

const fetchCounts = async () => {
  try {
    const { data } = await RequestsAPI.counts();
    counts.value = data;
  } catch {
    /* ignore */
  }
};

const fetchRequests = async () => {
  const { data } = await RequestsAPI.list({ filter: activeTab.value, page: 1 });
  requests.value = data.payload || [];
};

const setTab = key => {
  activeTab.value = key;
  selected.value = null;
  fetchRequests();
};

const openRequest = async row => {
  comment.value = '';
  const { data } = await RequestsAPI.get(row.id);
  selected.value = data;
};

const refreshAll = () => {
  fetchRequests();
  fetchCounts();
};

const act = async decision => {
  try {
    const fn =
      decision === 'approved' ? RequestsAPI.approve : RequestsAPI.reject;
    const { data } = await fn.call(
      RequestsAPI,
      selected.value.id,
      comment.value
    );
    selected.value = data;
    comment.value = '';
    useAlert(L.done);
    refreshAll();
  } catch {
    useAlert(L.error);
  }
};

const cancelRequest = async () => {
  try {
    const { data } = await RequestsAPI.cancel(selected.value.id);
    selected.value = data;
    useAlert(L.canceled);
    refreshAll();
  } catch {
    useAlert(L.error);
  }
};

// ---- 发起审批 ----
const openPicker = async () => {
  const { data } = await TemplatesAPI.get({ active: true });
  templates.value = data.payload || [];
  pickerRef.value?.open();
};

const pickTemplate = tpl => {
  activeTemplate.value = tpl;
  formValues.value = {};
  (tpl.formFields || tpl.form_fields || []).forEach(f => {
    formValues.value[f.key] = '';
  });
  attachments.value = [];
  selectedDeptId.value = myDepartments.value[0]
    ? String(myDepartments.value[0].department_id)
    : '';
  pickerRef.value?.close();
  formRef.value?.open();
};

const templateFields = computed(
  () =>
    activeTemplate.value?.formFields || activeTemplate.value?.form_fields || []
);

const onPickFiles = event => {
  attachments.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeAttachment = i => attachments.value.splice(i, 1);

const submitRequest = async () => {
  const missing = templateFields.value.some(
    f => f.required && !String(formValues.value[f.key] ?? '').trim()
  );
  if (missing || (needsDept.value && !selectedDeptId.value)) {
    useAlert(L.required);
    return;
  }
  try {
    if (attachments.value.length) {
      const fd = new FormData();
      fd.append('template_id', activeTemplate.value.id);
      if (selectedDeptId.value)
        fd.append('department_id', selectedDeptId.value);
      Object.entries(formValues.value).forEach(([k, v]) =>
        fd.append(`form_data[${k}]`, v ?? '')
      );
      attachments.value.forEach(f => fd.append('files[]', f));
      await RequestsAPI.submitForm(fd);
    } else {
      await RequestsAPI.submit({
        template_id: activeTemplate.value.id,
        department_id: selectedDeptId.value || null,
        form_data: formValues.value,
      });
    }
    formRef.value?.close();
    useAlert(L.submitted);
    activeTab.value = 'mine';
    selected.value = null;
    refreshAll();
  } catch {
    useAlert(L.error);
  }
};

// 详情里按模板字段渲染表单值
const detailFields = computed(
  () => selected.value?.formFields || selected.value?.form_fields || []
);

onMounted(async () => {
  fetchRequests();
  fetchCounts();
  try {
    const [{ data: mine }, { data: ags }] = await Promise.all([
      MembershipsAPI.get({ mine: 'true' }),
      AgentAPI.get(),
    ]);
    myDepartments.value = mine.payload || [];
    agents.value = ags || [];
  } catch {
    /* ignore */
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/55 backdrop-blur-2xl rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
      <Button
        :label="L.start"
        icon="i-lucide-plus"
        color="iris"
        @click="openPicker"
      />
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 左：列表 -->
      <section
        class="flex flex-col flex-shrink-0 border-r w-[380px] border-n-weak bg-n-solid-1"
      >
        <div class="flex items-center gap-1 px-3 py-2 border-b border-n-weak">
          <button
            v-for="tab in TABS"
            :key="tab.key"
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg transition-colors"
            :class="
              activeTab === tab.key
                ? 'bg-n-iris-3 text-n-iris-11 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="setTab(tab.key)"
          >
            {{ tab.label }}
            <span
              v-if="tab.key === 'todo' && counts.todo"
              class="px-1.5 rounded-full text-[11px] bg-n-iris-9 text-white"
            >
              {{ counts.todo }}
            </span>
          </button>
        </div>
        <div class="flex-1 overflow-y-auto">
          <div
            v-if="!requests.length"
            class="p-8 text-sm text-center text-n-slate-10"
          >
            {{ L.empty }}
          </div>
          <button
            v-for="row in requests"
            :key="row.id"
            class="flex w-full gap-3 px-4 py-3 text-left border-b border-n-weak transition-colors"
            :class="
              selected && selected.id === row.id
                ? 'bg-n-iris-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="openRequest(row)"
          >
            <div
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-9 bg-n-iris-4 text-n-iris-11"
            >
              <Icon
                :icon="row.template_icon || 'i-lucide-file-check'"
                class="size-4"
              />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center justify-between gap-2">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ row.title }}
                </span>
                <span
                  class="px-1.5 py-0.5 rounded text-[11px] flex-shrink-0"
                  :class="STATUS_META[row.status]?.class"
                >
                  {{ STATUS_META[row.status]?.label }}
                </span>
              </div>
              <div class="mt-0.5 text-xs truncate text-n-slate-10">
                {{ `${row.template_name} · ${row.applicant_name}` }}
              </div>
              <div class="mt-0.5 text-[11px] text-n-slate-9">
                {{ fmtDateTime(row.submitted_at || row.created_at) }}
              </div>
            </div>
          </button>
        </div>
      </section>

      <!-- 右：详情 -->
      <section class="flex flex-col flex-1 min-w-0">
        <div
          v-if="!selected"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <Icon icon="i-lucide-file-check" class="size-12 opacity-40" />
          <p class="text-sm">{{ L.selectHint }}</p>
        </div>

        <template v-else>
          <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak">
            <h2 class="text-base font-medium truncate text-n-slate-12">
              {{ selected.title }}
            </h2>
            <span
              class="px-2 py-0.5 rounded-full text-xs flex-shrink-0"
              :class="STATUS_META[selected.status]?.class"
            >
              {{ STATUS_META[selected.status]?.label }}
            </span>
          </div>

          <div class="flex-1 p-6 overflow-y-auto">
            <div class="flex items-center gap-2 mb-4 text-sm text-n-slate-11">
              <div
                class="flex items-center justify-center rounded-full size-7 bg-n-iris-4 text-n-iris-11 text-xs"
              >
                {{ initial(selected.applicant_name) }}
              </div>
              {{ `${L.applicant}：${selected.applicant_name}` }}
              <span class="text-n-slate-10">
                {{ fmtDateTime(selected.submitted_at) }}
              </span>
            </div>

            <!-- 表单内容 -->
            <div
              class="grid grid-cols-2 gap-3 p-4 mb-6 rounded-xl bg-n-alpha-1"
            >
              <div v-if="selected.department_name" class="min-w-0">
                <div class="text-[11px] text-n-slate-10">{{ L.dept }}</div>
                <div class="text-sm text-n-slate-12">
                  {{ selected.department_name }}
                </div>
              </div>
              <div v-for="f in detailFields" :key="f.key" class="min-w-0">
                <div class="text-[11px] text-n-slate-10">{{ f.label }}</div>
                <div class="text-sm break-words text-n-slate-12">
                  {{ selected.form_data?.[f.key] || '—' }}
                </div>
              </div>
            </div>

            <!-- 附件 -->
            <div v-if="selected.files?.length" class="mb-6">
              <p class="mb-2 text-xs font-medium text-n-slate-10">
                {{ L.attachments }}
              </p>
              <div class="grid grid-cols-2 gap-2">
                <a
                  v-for="file in selected.files"
                  :key="file.id"
                  :href="file.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center gap-2 p-2 text-sm border rounded-lg border-n-weak hover:bg-n-alpha-1"
                >
                  <Icon icon="i-lucide-file" class="size-4 text-n-iris-11" />
                  <span class="truncate text-n-slate-12">{{
                    file.filename
                  }}</span>
                </a>
              </div>
            </div>

            <!-- 审批流程时间轴 -->
            <p class="mb-3 text-xs font-medium text-n-slate-10">{{ L.flow }}</p>
            <div class="flex flex-col gap-4">
              <div
                v-for="step in selected.steps"
                :key="step.id"
                class="flex gap-3"
              >
                <div
                  class="flex items-center justify-center flex-shrink-0 border rounded-full size-7 border-n-weak bg-n-solid-1"
                  :class="STEP_META[step.status]?.class"
                >
                  <Icon :icon="STEP_META[step.status]?.icon" class="size-4" />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 text-sm text-n-slate-12">
                    {{ step.approver_name || '（未指定）' }}
                    <span
                      v-if="step.is_current"
                      class="px-1.5 rounded text-[10px] bg-n-iris-3 text-n-iris-11"
                    >
                      {{ L.current }}
                    </span>
                  </div>
                  <div v-if="step.comment" class="text-xs text-n-slate-11">
                    {{ step.comment }}
                  </div>
                  <div v-if="step.acted_at" class="text-[11px] text-n-slate-9">
                    {{ fmtDateTime(step.acted_at) }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- 操作区 -->
          <div
            v-if="
              selected.can_act ||
              (selected.is_applicant && selected.status === 'pending')
            "
            class="flex-shrink-0 p-4 border-t border-n-weak bg-n-solid-1"
          >
            <textarea
              v-if="selected.can_act"
              v-model="comment"
              rows="2"
              :placeholder="L.commentPlaceholder"
              class="w-full px-3 py-2 mb-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
            />
            <div class="flex gap-2">
              <template v-if="selected.can_act">
                <Button
                  :label="L.approve"
                  icon="i-lucide-check"
                  color="teal"
                  @click="act('approved')"
                />
                <Button
                  :label="L.reject"
                  icon="i-lucide-x"
                  color="ruby"
                  variant="faded"
                  @click="act('rejected')"
                />
              </template>
              <Button
                v-if="selected.is_applicant && selected.status === 'pending'"
                :label="L.cancel"
                icon="i-lucide-undo-2"
                color="slate"
                variant="faded"
                @click="cancelRequest"
              />
            </div>
          </div>
        </template>
      </section>
    </div>

    <!-- 选模板 -->
    <Dialog
      ref="pickerRef"
      :title="L.pickTemplate"
      :show-confirm-button="false"
    >
      <div class="grid grid-cols-2 gap-3">
        <button
          v-for="tpl in templates"
          :key="tpl.id"
          class="flex items-center gap-3 p-4 text-left border rounded-xl border-n-weak hover:border-n-iris-7 hover:bg-n-alpha-1"
          @click="pickTemplate(tpl)"
        >
          <div
            class="flex items-center justify-center rounded-lg size-10 bg-n-iris-4 text-n-iris-11"
          >
            <Icon :icon="tpl.icon || 'i-lucide-file-check'" class="size-5" />
          </div>
          <div class="min-w-0">
            <div class="text-sm font-medium truncate text-n-slate-12">
              {{ tpl.name }}
            </div>
            <div
              v-if="tpl.description"
              class="text-xs truncate text-n-slate-10"
            >
              {{ tpl.description }}
            </div>
          </div>
        </button>
      </div>
    </Dialog>

    <!-- 填表单 -->
    <Dialog
      ref="formRef"
      :title="activeTemplate?.name"
      :confirm-button-label="L.submit"
      confirm-button-color="iris"
      @confirm="submitRequest"
    >
      <div class="flex flex-col gap-4">
        <div v-for="f in templateFields" :key="f.key">
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ f.label }}{{ f.required ? ' *' : '' }}
          </label>
          <textarea
            v-if="f.type === 'textarea'"
            v-model="formValues[f.key]"
            rows="3"
            class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
          <select
            v-else-if="f.type === 'select'"
            v-model="formValues[f.key]"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          >
            <option value="">{{ '请选择' }}</option>
            <option v-for="opt in f.options || []" :key="opt" :value="opt">
              {{ opt }}
            </option>
          </select>
          <input
            v-else
            v-model="formValues[f.key]"
            :type="
              f.type === 'number' || f.type === 'amount'
                ? 'number'
                : f.type === 'date'
                  ? 'date'
                  : 'text'
            "
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
          <p
            v-if="f.type === 'amount' && formValues[f.key]"
            class="mt-1 text-xs text-n-slate-10"
          >
            {{ `${L.upper}${amountToWords(formValues[f.key])}` }}
          </p>
        </div>

        <!-- 所在部门 -->
        <div v-if="needsDept">
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ `${L.dept} *` }}
          </label>
          <select
            v-model="selectedDeptId"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          >
            <option value="">{{ L.deptPlaceholder }}</option>
            <option
              v-for="d in myDepartments"
              :key="d.id"
              :value="String(d.department_id)"
            >
              {{ d.department_name }}
            </option>
          </select>
        </div>

        <!-- 附件 -->
        <div>
          <label class="block mb-1 text-heading-3 text-n-slate-12">
            {{ L.attachments }}
          </label>
          <input
            ref="fileInputRef"
            type="file"
            multiple
            class="hidden"
            @change="onPickFiles"
          />
          <button
            class="inline-flex items-center gap-1.5 px-3 h-9 text-sm border rounded-lg border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            @click="fileInputRef?.click()"
          >
            <Icon icon="i-lucide-plus" class="size-4" />
            {{ L.addAttachment }}
          </button>
          <div v-if="attachments.length" class="flex flex-col gap-1.5 mt-2">
            <div
              v-for="(file, i) in attachments"
              :key="i"
              class="flex items-center justify-between gap-2 px-3 py-1.5 text-sm border rounded-lg border-n-weak"
            >
              <span class="flex items-center min-w-0 gap-2">
                <Icon icon="i-lucide-file" class="size-4 text-n-iris-11" />
                <span class="truncate text-n-slate-12">{{ file.name }}</span>
              </span>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeAttachment(i)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <!-- 流程预览 -->
        <div v-if="flowPreview.length" class="pt-3 border-t border-n-weak">
          <p class="mb-2 text-xs font-medium text-n-slate-10">
            {{ L.flowPreview }}
          </p>
          <div class="flex flex-wrap items-center gap-1.5">
            <template v-for="(name, i) in flowPreview" :key="i">
              <Icon
                v-if="i > 0"
                icon="i-lucide-chevron-right"
                class="size-3.5 text-n-slate-9"
              />
              <span
                class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
              >
                <span
                  class="flex items-center justify-center rounded-full size-4 bg-n-iris-9 text-white text-[10px]"
                >
                  {{ i + 1 }}
                </span>
                {{ name }}
              </span>
            </template>
          </div>
        </div>
      </div>
    </Dialog>
  </div>
</template>
