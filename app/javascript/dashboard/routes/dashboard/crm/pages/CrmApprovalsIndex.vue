<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import TemplatesAPI from 'dashboard/api/oa/approvalTemplates';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';

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
};

const STATUS_META = {
  pending: { label: '审批中', class: 'bg-n-amber-3 text-n-amber-11' },
  approved: { label: '已通过', class: 'bg-n-teal-3 text-n-teal-11' },
  rejected: { label: '已驳回', class: 'bg-n-ruby-3 text-n-ruby-11' },
  canceled: { label: '已撤回', class: 'bg-n-slate-3 text-n-slate-11' },
};
const STEP_META = {
  pending: { icon: 'i-lucide-clock', class: 'text-n-amber-11' },
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
  pickerRef.value?.close();
  formRef.value?.open();
};

const templateFields = computed(
  () =>
    activeTemplate.value?.formFields || activeTemplate.value?.form_fields || []
);

const submitRequest = async () => {
  const missing = templateFields.value.some(
    f => f.required && !String(formValues.value[f.key] ?? '').trim()
  );
  if (missing) {
    useAlert(L.required);
    return;
  }
  try {
    await RequestsAPI.submit({
      template_id: activeTemplate.value.id,
      form_data: formValues.value,
    });
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

onMounted(() => {
  fetchRequests();
  fetchCounts();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">{{ L.header }}</h1>
      <Button
        :label="L.start"
        icon="i-lucide-plus"
        color="amber"
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
                ? 'bg-n-amber-3 text-n-amber-11 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="setTab(tab.key)"
          >
            {{ tab.label }}
            <span
              v-if="tab.key === 'todo' && counts.todo"
              class="px-1.5 rounded-full text-[11px] bg-n-amber-9 text-white"
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
                ? 'bg-n-amber-2'
                : 'hover:bg-n-alpha-1'
            "
            @click="openRequest(row)"
          >
            <div
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-9 bg-n-amber-4 text-n-amber-11"
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
                class="flex items-center justify-center rounded-full size-7 bg-n-amber-4 text-n-amber-11 text-xs"
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
              <div v-for="f in detailFields" :key="f.key" class="min-w-0">
                <div class="text-[11px] text-n-slate-10">{{ f.label }}</div>
                <div class="text-sm break-words text-n-slate-12">
                  {{ selected.form_data?.[f.key] || '—' }}
                </div>
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
                      class="px-1.5 rounded text-[10px] bg-n-amber-3 text-n-amber-11"
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
              class="w-full px-3 py-2 mb-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
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
          class="flex items-center gap-3 p-4 text-left border rounded-xl border-n-weak hover:border-n-amber-7 hover:bg-n-alpha-1"
          @click="pickTemplate(tpl)"
        >
          <div
            class="flex items-center justify-center rounded-lg size-10 bg-n-amber-4 text-n-amber-11"
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
      confirm-button-color="amber"
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
            class="w-full px-3 py-2 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
          />
          <select
            v-else-if="f.type === 'select'"
            v-model="formValues[f.key]"
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
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
            class="w-full h-10 px-3 text-sm border rounded-lg reset-base border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-amber-9"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
