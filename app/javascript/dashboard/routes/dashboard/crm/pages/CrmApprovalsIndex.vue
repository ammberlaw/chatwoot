<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import TemplatesAPI from 'dashboard/api/oa/approvalTemplates';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import MembershipsAPI from 'dashboard/api/org/memberships';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { flowNeedsDept } from 'dashboard/helper/oaApprovalFlow';

const L = {
  header: '审批中心',
  start: '发起审批',
  tabTodo: '待我审批',
  tabMine: '我发起的',
  tabDone: '我已审批',
  tabCc: '抄送我的',
  empty: '暂无审批单',
  selectHint: '选择左侧审批单查看详情',
  pickTemplate: '选择审批类型',
  submit: '提交',
  editAction: '修改',
  saved: '已保存',
  approve: '同意',
  reject: '驳回',
  cancel: '撤回',
  commentPlaceholder: '审批意见（可选）',
  applicant: '申请人',
  flow: '审批流程',
  cc: '抄送人',
  required: '请填写必填项',
  submitted: '已提交',
  done: '已处理',
  canceled: '已撤回',
  revoke: '销假',
  revokeTitle: '销假（撤销未开始的请假）',
  revokeSubmit: '提交销假',
  revokeDone: '销假单已提交，待审批通过后考勤自动撤回',
  revokeRangeInvalid: '起始日期不能晚于结束日期',
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
  conditional: '按条件判定',
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

const activeTab = ref('todo');
const requests = ref([]);
const counts = ref({ todo: 0, mine: 0, cc: 0, approver_view: true });

// 非审批人（业务员/普通成员且未被指定为审批人）隐藏「待我审批」
const showTodo = computed(() => counts.value.approver_view !== false);
// 「抄送我的」：管理层（管理员/副管理员/部门主管）+ 财务（报销/付款等审批常抄送财务）；
// 或任何实际被抄送过的人（cc>0），确保被点名抄送者一定看得到。
const { isAdmin, isCrmDeputyAdmin, isCrmManager, isCrmFinance } = useCrmRole();
const showCc = computed(
  () =>
    isAdmin.value ||
    isCrmDeputyAdmin.value ||
    isCrmManager.value ||
    isCrmFinance.value ||
    counts.value.cc > 0
);
const TABS = computed(() =>
  [
    showTodo.value ? { key: 'todo', label: L.tabTodo } : null,
    // 我已审批：审批人(或曾处理过审批者)可见，紧挨「待我审批」成对。
    showTodo.value || counts.value.done > 0
      ? { key: 'done', label: L.tabDone }
      : null,
    { key: 'mine', label: L.tabMine },
    showCc.value ? { key: 'cc', label: L.tabCc } : null,
  ].filter(Boolean)
);
const selected = ref(null);
const comment = ref('');

const templates = ref([]);
const pickerRef = ref(null);
const formRef = ref(null);
const activeTemplate = ref(null);
const formValues = ref({});
const { isDirty, markPristine } = useDirtyGuard(() => formValues.value);
const myDepartments = ref([]);
const agents = ref([]);
const selectedDeptId = ref('');
const attachments = ref([]);

// —— 附件在线预览 ——
// 报销单的附件九成是发票/小票截图，原来只能点开新标签页下载下来看，
// 批一张单要下载七八张图、看完还得回来找回这张单。图片和 PDF 就地弹窗看。
const IMAGE_EXT = /\.(png|jpe?g|gif|webp|bmp|svg)$/i;
const PDF_EXT = /\.pdf$/i;
const previewKind = file => {
  const n = file?.filename || '';
  if (IMAGE_EXT.test(n)) return 'image';
  if (PDF_EXT.test(n)) return 'pdf';
  return null;
};
const previewRef = ref(null);
const previewFile = ref(null);
// 同一张单里的可预览附件，用来在弹窗里左右翻——发票是一组一组看的。
const previewList = computed(() =>
  (selected.value?.files || []).filter(f => previewKind(f))
);
// 不可预览的（压缩包、Office 文档等）仍是下载链接。
const downloadOnlyFiles = computed(() =>
  (selected.value?.files || []).filter(f => !previewKind(f))
);
const previewIndex = computed(() =>
  previewList.value.findIndex(f => f.id === previewFile.value?.id)
);
const openPreview = file => {
  if (!previewKind(file)) return; // 不认识的类型仍走下载
  previewFile.value = file;
  previewRef.value?.open();
};
const stepPreview = delta => {
  const list = previewList.value;
  if (list.length < 2) return;
  const next = (previewIndex.value + delta + list.length) % list.length;
  previewFile.value = list[next];
};
const fileInputRef = ref(null);
// 编辑态：editingId 非空表示改单(而非新发起)；existingFiles 为该单既有附件、removeFileIds 为勾删的附件 id。
const editingId = ref(null);
const existingFiles = ref([]);
const removeFileIds = ref([]);

const templateFlow = computed(
  () => activeTemplate.value?.flow || activeTemplate.value?.flow || []
);
const needsDept = computed(() => flowNeedsDept(templateFlow.value));
const pickedDept = computed(() =>
  myDepartments.value.find(
    d => String(d.department_id) === selectedDeptId.value
  )
);

// 提交前预览审批链：部门主管→所选部门负责人；指定成员→该成员。
// 条件分支要等提交时按填写内容才定得下来，这里只标一格「按条件判定」。
const flowPreview = computed(() =>
  templateFlow.value.map(step => {
    if (step.type === 'condition') return L.conditional;
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

// 详情表单值展示：datetime 字段把 "2026-09-01T14:30" 显示成 "2026-09-01 14:30"
const displayFieldValue = (f, data) => {
  const v = data?.[f.key];
  if (v == null || v === '') return '—';
  return f.type === 'datetime' ? String(v).replace('T', ' ') : v;
};

// 发起表单里各字段对应的原生 input type。
const FIELD_INPUT_TYPES = {
  number: 'number',
  amount: 'number',
  date: 'date',
  datetime: 'datetime-local',
};
const fieldInputType = f => FIELD_INPUT_TYPES[f.type] || 'text';

// 日期/时间字段用紫玻璃 DatePicker（日级）+ 时间下拉（半小时步长）替换原生 input。
// datetime 字段值存 "YYYY-MM-DDTHH:MM"，拆成日期段/时间段分别编辑再拼回。
const TIME_OPTIONS = [
  { value: '', label: '时间' },
  ...Array.from({ length: 48 }, (_, i) => {
    const hh = String(Math.floor(i / 2)).padStart(2, '0');
    const mm = i % 2 === 0 ? '00' : '30';
    return { value: `${hh}:${mm}`, label: `${hh}:${mm}` };
  }),
];
const dtDate = key => (formValues.value[key] || '').split('T')[0] || '';
const dtTime = key => (formValues.value[key] || '').split('T')[1] || '';
const setDtDate = (key, v) => {
  formValues.value[key] = v ? `${v}T${dtTime(key) || '09:00'}` : '';
};
const setDtTime = (key, v) => {
  const d = dtDate(key);
  if (!d) {
    formValues.value[key] = '';
    return;
  }
  formValues.value[key] = `${d}T${v || '00:00'}`;
};

// 默认部门：申请人的首个部门（没有则空）。
const firstDeptId = () =>
  myDepartments.value[0] ? String(myDepartments.value[0].department_id) : '';

const fetchRequests = async () => {
  const { data } = await RequestsAPI.list({ filter: activeTab.value, page: 1 });
  requests.value = data.payload || [];
};

const fetchCounts = async () => {
  try {
    const { data } = await RequestsAPI.counts();
    counts.value = data;
    // 非审批人回退「我的」；非管理层落在「抄送我的」也回退（该 Tab 已隐藏）。
    if (
      (data.approver_view === false && activeTab.value === 'todo') ||
      (!showCc.value && activeTab.value === 'cc')
    ) {
      activeTab.value = 'mine';
      fetchRequests();
    }
  } catch {
    /* ignore */
  }
};

const setTab = key => {
  activeTab.value = key;
  selected.value = null;
  fetchRequests();
};

const openRequest = async row => {
  comment.value = '';
  const { data } = await RequestsAPI.show(row.id);
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
  editingId.value = null;
  activeTemplate.value = tpl;
  formValues.value = {};
  (tpl.formFields || tpl.form_fields || []).forEach(f => {
    formValues.value[f.key] = '';
  });
  attachments.value = [];
  existingFiles.value = [];
  removeFileIds.value = [];
  selectedDeptId.value = myDepartments.value[0]
    ? String(myDepartments.value[0].department_id)
    : '';
  pickerRef.value?.close();
  markPristine();
  formRef.value?.open();
};

// 修改已发起的审批单（审批中且尚无人处理时可用）：用当前单的表单值/部门/附件回填同一个发起表单。
const openEditRequest = () => {
  const r = selected.value;
  if (!r) return;
  editingId.value = r.id;
  activeTemplate.value = {
    id: r.template_id,
    name: r.template_name,
    formFields: r.form_fields || [],
    flow: r.flow || [],
  };
  formValues.value = {};
  (r.form_fields || []).forEach(f => {
    formValues.value[f.key] = r.form_data?.[f.key] ?? '';
  });
  attachments.value = [];
  existingFiles.value = [...(r.files || [])];
  removeFileIds.value = [];
  selectedDeptId.value = r.department_id
    ? String(r.department_id)
    : firstDeptId();
  markPristine();
  formRef.value?.open();
};

const removeExistingFile = file => {
  removeFileIds.value.push(file.id);
  existingFiles.value = existingFiles.value.filter(f => f.id !== file.id);
};

const templateFields = computed(
  () =>
    activeTemplate.value?.formFields || activeTemplate.value?.form_fields || []
);

// 原生 select → 紫玻璃 SelectCard 选项（保留原首个「请选择」空值项）。
const fieldSelectOptions = f => [
  { value: '', label: '请选择' },
  ...(f.options || []).map(opt => ({ value: opt, label: opt })),
];
const deptOptions = computed(() => [
  { value: '', label: L.deptPlaceholder },
  ...myDepartments.value.map(d => ({
    value: String(d.department_id),
    label: d.department_name,
  })),
]);

const onPickFiles = event => {
  attachments.value.push(...Array.from(event.target.files || []));
  event.target.value = '';
};
const removeAttachment = i => attachments.value.splice(i, 1);

// 表单值 + 附件打包成 multipart（新发起 / 修改共用）。
const buildFormData = () => {
  const fd = new FormData();
  if (selectedDeptId.value) fd.append('department_id', selectedDeptId.value);
  Object.entries(formValues.value).forEach(([k, v]) =>
    fd.append(`form_data[${k}]`, v ?? '')
  );
  attachments.value.forEach(f => fd.append('files[]', f));
  return fd;
};

const submitRequest = async () => {
  const missing = templateFields.value.some(
    f => f.required && !String(formValues.value[f.key] ?? '').trim()
  );
  if (missing || (needsDept.value && !selectedDeptId.value)) {
    useAlert(L.required);
    return;
  }
  try {
    if (editingId.value) {
      const id = editingId.value;
      // 有新增/删除附件走 multipart，否则纯 JSON。
      if (attachments.value.length || removeFileIds.value.length) {
        const fd = buildFormData();
        removeFileIds.value.forEach(fid => fd.append('remove_file_ids[]', fid));
        await RequestsAPI.updateForm(id, fd);
      } else {
        await RequestsAPI.update(id, {
          department_id: selectedDeptId.value || null,
          form_data: formValues.value,
        });
      }
      formRef.value?.close();
      editingId.value = null;
      useAlert(L.saved);
      await openRequest({ id }); // 重新拉详情，展示修改后的单
      refreshAll();
    } else {
      if (attachments.value.length) {
        const fd = buildFormData();
        fd.append('template_id', activeTemplate.value.id);
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
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
  }
};

// ---- 销假 ----
// 只能销「今天及以后」的假：过去的日子人确实没来上班，销掉等于把考勤改成正常。
// 后端 AttendanceRevokeService 同样兜了这条，这里只是别让人填了才被拒。
const revokeRef = ref(null);
const revokeFrom = ref('');
const revokeTo = ref('');
const revoking = ref(false);
const todayStr = () => new Date().toLocaleDateString('sv-SE'); // YYYY-MM-DD（本地时区）

// 原单的日期字段：date 与 datetime 都算（datetime 值形如 2026-09-23T09:00，
// 取 T 前面的日期部分参与区间计算，销假仍以「天」为单位）。
const DATE_FIELD_TYPES = ['date', 'datetime'];
const originalDateKeys = computed(() =>
  detailFields.value
    .filter(f => DATE_FIELD_TYPES.includes(f.type))
    .map(f => f.key)
);
const originalDates = computed(() =>
  originalDateKeys.value
    .map(k => String(selected.value?.form_data?.[k] || '').split('T')[0])
    .filter(v => !!v)
    .sort()
);
// 可销区间 = 原单区间与「今天起」的交集
const revokeMin = computed(() => {
  const start = originalDates.value[0] || todayStr();
  return start > todayStr() ? start : todayStr();
});
const revokeMax = computed(
  () => originalDates.value[originalDates.value.length - 1] || ''
);

const openRevoke = () => {
  revokeFrom.value = revokeMin.value;
  revokeTo.value = revokeMax.value || revokeMin.value;
  revokeRef.value?.open();
};

const submitRevoke = async () => {
  if (!revokeFrom.value || !revokeTo.value || revoking.value) return;
  if (revokeFrom.value > revokeTo.value) {
    useAlert(L.revokeRangeInvalid);
    return;
  }
  revoking.value = true;
  try {
    // 销假单复用原模板，所以 form_data 的键也要用原模板的日期字段：
    // 两个日期字段=起止各填一个；只有一个字段=按单日销。
    const keys = originalDateKeys.value;
    const formData = {};
    if (keys.length >= 2) {
      formData[keys[0]] = revokeFrom.value;
      formData[keys[keys.length - 1]] = revokeTo.value;
    } else if (keys.length === 1) {
      formData[keys[0]] = revokeFrom.value;
    }
    await RequestsAPI.revoke(selected.value.id, formData);
    revokeRef.value?.close();
    useAlert(L.revokeDone);
    refreshAll();
  } catch (e) {
    useAlert(e?.response?.data?.error || L.error);
  } finally {
    revoking.value = false;
  }
};

// 详情里按模板字段渲染表单值
const detailFields = computed(
  () => selected.value?.formFields || selected.value?.form_fields || []
);

const route = useRoute();
// 从考勤页深链：?compose=reclock|leave 自动打开对应考勤联动模板的发起表单。
const openComposeFromQuery = async () => {
  const kind = route.query.compose;
  if (!kind) return;
  try {
    const { data } = await TemplatesAPI.get({ active: true });
    templates.value = data.payload || [];
    const tpl = templates.value.find(
      t => (t.attendanceKind || t.attendance_kind) === kind
    );
    if (tpl) pickTemplate(tpl);
    else useAlert('没有找到对应的审批模板，请先在「审批模板」里配置');
  } catch {
    /* ignore */
  }
};

onMounted(async () => {
  await fetchCounts();
  fetchRequests();
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
  openComposeFromQuery();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-xl font-medium truncate text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
        {{ L.header }}
      </h1>
      <Button
        :label="L.start"
        icon="i-lucide-plus"
        color="iris"
        @click="openPicker"
      />
    </div>

    <div class="flex flex-1 min-h-0">
      <!-- 左：列表（手机：仅未选中时全宽显示） -->
      <section
        class="flex-col flex-shrink-0 w-full border-r md:flex md:w-[420px] border-n-weak bg-n-solid-1"
        :class="selected ? 'hidden' : 'flex'"
      >
        <!-- 四个 tab 要塞进左栏：带角标时原来会被压到「待我审 / 批」两行。
             故一律不换行 + 不被压缩，栏宽放到 420px；真放不下（窄屏/更多 tab）就横向滚，不再折行。 -->
        <div class="px-2 overflow-x-auto border-b border-n-weak">
          <div data-tabbar="page" class="whitespace-nowrap">
            <button
              v-for="tab in TABS"
              :key="tab.key"
              class="shrink-0"
              :aria-selected="activeTab === tab.key"
              @click="setTab(tab.key)"
            >
              {{ tab.label }}
              <span
                v-if="['todo', 'cc'].includes(tab.key) && counts[tab.key]"
                class="px-1.5 rounded-full text-[11px] bg-n-iris-9 text-white"
              >
                {{ counts[tab.key] }}
              </span>
            </button>
          </div>
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

      <!-- 右：详情（手机：仅选中时全宽显示） -->
      <section
        class="flex-col flex-1 min-w-0 md:flex"
        :class="selected ? 'flex' : 'hidden'"
      >
        <div
          v-if="!selected"
          class="flex flex-col items-center justify-center flex-1 gap-3 text-n-slate-10"
        >
          <Icon icon="i-lucide-file-check" class="size-12 opacity-40" />
          <p class="text-sm">{{ L.selectHint }}</p>
        </div>

        <template v-else>
          <div
            class="flex items-center gap-3 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak"
          >
            <button
              class="flex items-center justify-center flex-shrink-0 rounded-lg size-8 text-n-slate-11 hover:bg-n-alpha-1 md:hidden"
              @click="selected = null"
            >
              <Icon icon="i-lucide-arrow-left" class="size-5" />
            </button>
            <h2 class="min-w-0 text-base font-medium truncate text-n-slate-12">
              {{ selected.title }}
            </h2>
            <span
              class="px-2 py-0.5 rounded-full text-xs flex-shrink-0"
              :class="STATUS_META[selected.status]?.class"
            >
              {{ STATUS_META[selected.status]?.label }}
            </span>
          </div>

          <div class="flex-1 p-4 overflow-y-auto sm:p-6">
            <div class="flex items-center gap-2 mb-4 text-sm text-n-slate-11">
              <Avatar
                :name="selected.applicant_name"
                :src="selected.applicant_avatar_url || ''"
                :size="28"
                rounded-full
              />
              {{ `${L.applicant}：${selected.applicant_name}` }}
              <span class="text-n-slate-10">
                {{ fmtDateTime(selected.submitted_at) }}
              </span>
            </div>

            <!-- 表单内容 -->
            <div
              class="grid grid-cols-1 gap-3 p-4 mb-6 sm:grid-cols-2 rounded-xl bg-n-alpha-1"
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
                  {{ displayFieldValue(f, selected.form_data) }}
                </div>
              </div>
            </div>

            <!-- 附件 -->
            <div v-if="selected.files?.length" class="mb-6">
              <p class="mb-2 text-xs font-medium text-n-slate-10">
                {{ L.attachments }}
              </p>
              <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <!-- 图片/PDF 就地弹窗看（报销附件几乎都是发票截图，下载下来看太绕）；
                     其余类型仍是下载链接。 -->
                <button
                  v-for="file in previewList"
                  :key="file.id"
                  type="button"
                  class="flex items-center w-full gap-2 p-2 text-sm text-left border rounded-lg reset-base border-n-weak hover:bg-n-alpha-1"
                  @click="openPreview(file)"
                >
                  <Icon
                    :icon="
                      previewKind(file) === 'pdf'
                        ? 'i-lucide-file-text'
                        : 'i-lucide-image'
                    "
                    class="size-4 shrink-0 text-n-iris-11"
                  />
                  <span class="flex-1 min-w-0 truncate text-n-slate-12">
                    {{ file.filename }}
                  </span>
                  <Icon
                    icon="i-lucide-eye"
                    class="size-3.5 shrink-0 text-n-slate-10"
                  />
                </button>
                <a
                  v-for="file in downloadOnlyFiles"
                  :key="`dl-${file.id}`"
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

            <!-- 抄送人 -->
            <div v-if="selected.cc_names?.length" class="mt-6">
              <p class="mb-2 text-xs font-medium text-n-slate-10">{{ L.cc }}</p>
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="name in selected.cc_names"
                  :key="name"
                  class="px-2 py-0.5 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
                >
                  {{ name }}
                </span>
              </div>
            </div>
          </div>

          <!-- 操作区：待我审批 / 申请人改撤（审批中）/ 申请人销假（已通过的考勤类单） -->
          <div
            v-if="
              selected.can_act ||
              (selected.is_applicant && selected.status === 'pending') ||
              (selected.is_applicant && selected.revokable)
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
                  color="iris"
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
                :label="L.editAction"
                icon="i-lucide-pencil"
                color="iris"
                variant="faded"
                @click="openEditRequest"
              />
              <Button
                v-if="selected.is_applicant && selected.status === 'pending'"
                :label="L.cancel"
                icon="i-lucide-undo-2"
                color="slate"
                variant="faded"
                @click="cancelRequest"
              />
              <Button
                v-if="selected.is_applicant && selected.revokable"
                :label="L.revoke"
                icon="i-lucide-calendar-x"
                color="amber"
                variant="faded"
                @click="openRevoke"
              />
            </div>
          </div>
        </template>
      </section>
    </div>

    <!-- 销假：选实际要销的区间。起始日不早于今天（历史考勤只能走 HR 修正）-->
    <Dialog
      ref="revokeRef"
      :title="L.revokeTitle"
      :confirm-button-label="L.revokeSubmit"
      confirm-button-color="amber"
      :is-loading="revoking"
      @confirm="submitRevoke"
    >
      <div class="flex flex-col gap-4">
        <p class="text-sm text-n-slate-11">
          销假单会走原来那条审批链，审批通过后自动撤回对应日期的考勤。已经过去的日期不能销。
        </p>
        <div class="grid grid-cols-2 gap-3">
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">从</span>
            <input
              v-model="revokeFrom"
              type="date"
              :min="revokeMin"
              :max="revokeMax || undefined"
              class="w-full h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-sm font-medium text-n-slate-12">到</span>
            <input
              v-model="revokeTo"
              type="date"
              :min="revokeFrom || revokeMin"
              :max="revokeMax || undefined"
              class="w-full h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </div>
      </div>
    </Dialog>

    <!-- 选模板 -->
    <Dialog
      ref="pickerRef"
      :title="L.pickTemplate"
      :show-confirm-button="false"
    >
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
    <!-- overflow-y-auto：附件传多了表单会顶出屏幕、提交按钮够不着也滚不动（报销常传十几张发票）。 -->
    <Dialog
      ref="formRef"
      overflow-y-auto
      :title="activeTemplate?.name"
      :confirm-button-label="L.submit"
      confirm-button-color="iris"
      :dirty="isDirty"
      dirty-save-label="保存"
      @confirm="submitRequest"
      @close="markPristine"
      @save="submitRequest"
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
          <SelectCard
            v-else-if="f.type === 'select'"
            v-model="formValues[f.key]"
            :options="fieldSelectOptions(f)"
            block
          />
          <DatePicker
            v-else-if="f.type === 'date'"
            :model-value="formValues[f.key]"
            block
            @update:model-value="v => (formValues[f.key] = v)"
          />
          <div v-else-if="f.type === 'datetime'" class="flex gap-2">
            <DatePicker
              :model-value="dtDate(f.key)"
              block
              @update:model-value="v => setDtDate(f.key, v)"
            />
            <SelectCard
              :model-value="dtTime(f.key)"
              :options="TIME_OPTIONS"
              trigger-class="w-28"
              @update:model-value="v => setDtTime(f.key, v)"
            />
          </div>
          <input
            v-else
            v-model="formValues[f.key]"
            :type="fieldInputType(f)"
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
          <SelectCard v-model="selectedDeptId" :options="deptOptions" block />
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
          <!-- 编辑态：已有附件（可勾删） -->
          <div v-if="existingFiles.length" class="flex flex-col gap-1.5 mt-2">
            <div
              v-for="file in existingFiles"
              :key="file.id"
              class="flex items-center justify-between gap-2 px-3 py-1.5 text-sm border rounded-lg border-n-weak"
            >
              <span class="flex items-center min-w-0 gap-2">
                <Icon icon="i-lucide-file" class="size-4 text-n-iris-11" />
                <span class="truncate text-n-slate-12">{{
                  file.filename
                }}</span>
              </span>
              <button
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeExistingFile(file)"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
          </div>
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

    <!-- 附件在线预览：发票截图就地看完，不用下载一堆文件再回来找这张单 -->
    <Dialog
      ref="previewRef"
      :title="previewFile?.filename || '附件预览'"
      width="4xl"
      :show-cancel-button="false"
      :show-confirm-button="false"
    >
      <div v-if="previewFile" class="flex flex-col gap-3">
        <div
          class="flex items-center justify-center overflow-auto rounded-lg bg-n-alpha-1 min-h-[50vh] max-h-[70vh]"
        >
          <img
            v-if="previewKind(previewFile) === 'image'"
            :src="previewFile.url"
            :alt="previewFile.filename"
            class="object-contain max-w-full max-h-[70vh]"
          />
          <!-- PDF 交给浏览器自带阅读器；它不认的会自己提示下载 -->
          <iframe
            v-else
            :src="previewFile.url"
            :title="previewFile.filename"
            class="w-full h-[70vh] border-0"
          />
        </div>

        <div class="flex items-center gap-2">
          <!-- 一张报销单常有七八张发票，左右翻比关掉再点下一张快得多 -->
          <template v-if="previewList.length > 1">
            <Button
              icon="i-lucide-chevron-left"
              variant="ghost"
              size="sm"
              @click="stepPreview(-1)"
            />
            <span class="text-xs tabular-nums text-n-slate-11">
              {{ previewIndex + 1 }} / {{ previewList.length }}
            </span>
            <Button
              icon="i-lucide-chevron-right"
              variant="ghost"
              size="sm"
              @click="stepPreview(1)"
            />
          </template>
          <span class="flex-1" />
          <a
            :href="previewFile.url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs underline text-n-slate-11 underline-offset-2 hover:text-n-slate-12"
          >
            下载原件
          </a>
        </div>
      </div>
    </Dialog>
  </div>
</template>
