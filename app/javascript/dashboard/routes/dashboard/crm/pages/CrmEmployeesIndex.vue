<script setup>
/* global axios */
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';
import { useHrSensitiveSession } from 'dashboard/composables/useHrSensitiveSession';
import HrWorkbench from 'dashboard/components-next/HR/HrWorkbench.vue';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import { useAccount } from 'dashboard/composables/useAccount';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
const route = useRoute();
const { accountId } = useAccount();
let formGeneration = 0;
let listGeneration = 0;
let historyGeneration = 0;
const detailLoading = ref(false);
const fileBusy = ref(false);
const uploadTasks = ref([]);
const persistedSignature = ref('');
const pendingHandoverRetry = ref(false);
const workbenchRefresh = ref(0);
const canOffboard = ref(false);
const uploadKeys = new WeakMap();
const uploadKey = file => {
  if (!uploadKeys.has(file)) uploadKeys.set(file, crypto.randomUUID());
  return uploadKeys.get(file);
};
const api = () => `/api/v1/accounts/${accountId.value}/crm/employees`;

const STATUS = [
  ['ACTIVE', '在职'],
  ['PROBATION', '试用'],
  ['RESIGNED', '离职'],
];
const STATUS_LABEL = Object.fromEntries(STATUS);
const STATUS_STYLE = {
  ACTIVE: STATUS_TONE.done,
  PROBATION: STATUS_TONE.busy,
  RESIGNED: STATUS_TONE.idle,
};
const GENDER = [
  ['MALE', '男'],
  ['FEMALE', '女'],
];
const GENDER_LABEL = Object.fromEntries(GENDER);
const CONTRACT_TYPE = [
  ['FIRST', '首签'],
  ['RENEWAL', '续签'],
];
const RESIGN_TYPE = [
  ['VOLUNTARY', '主动'],
  ['INVOLUNTARY', '被动'],
];
const TABS = [['', '全部'], ...STATUS];

// ── 列表状态 ──
const employees = ref([]);
const departments = ref([]);
const loading = ref(false);
const tab = ref('');
const q = ref('');
const pendingDeleteId = ref(null);

// ── 表单状态（list / form 两种视图）──
const mode = ref('list');
const editingId = ref(null);
const saving = ref(false);
const errorMsg = ref('');
const form = reactive({
  employeeNo: '',
  name: '',
  gender: '',
  idCardNo: '',
  birthDate: '',
  nativePlace: '',
  departmentId: '',
  userId: '',
  jobTitle: '',
  jobCategory: '',
  workLocation: '',
  status: 'PROBATION',
  hireDate: '',
  regularDate: '',
  probationMonths: '',
  contractStartDate: '',
  contractEndDate: '',
  contractType: '',
  renewCount: '',
  salaryNote: '',
  bankCardNo: '',
  bankName: '',
  phone: '',
  email: '',
  wechat: '',
  resignDate: '',
  resignReason: '',
  resignType: '',
  handoverMode: 'pool',
  handoverTargetId: '',
});
// 已保存的附件（编辑时展示，可删）与待上传附件（保存后统一上传）
const photoUrl = ref(null);
const entryFiles = ref([]);
const resignFiles = ref([]);
const pendingPhoto = ref(null);
const pendingPhotoPreview = ref(null);
const pendingEntry = ref([]);
const pendingResign = ref([]);

const { isDirty, markPristine } = useDirtyGuard(() =>
  mode.value === 'form'
    ? {
        fields: { ...form },
        photo: pendingPhoto.value && [
          pendingPhoto.value.name,
          pendingPhoto.value.size,
          pendingPhoto.value.lastModified,
        ],
        entry: pendingEntry.value.map(file => [
          file.name,
          file.size,
          file.lastModified,
        ]),
        resign: pendingResign.value.map(file => [
          file.name,
          file.size,
          file.lastModified,
        ]),
      }
    : null
);
const mayDiscard = () => !isDirty.value || window.confirm(label('UNSAVED'));

const {
  active: sudoActive,
  checking: sudoChecking,
  password: sudoPassword,
  error: sudoError,
  verifying: sudoVerifying,
  unlock,
  handleError: handleSensitiveError,
} = useHrSensitiveSession();

const fetchList = async () => {
  listGeneration += 1;
  const request = listGeneration;
  loading.value = true;
  try {
    const { data } = await axios.get(api());
    if (request === listGeneration) employees.value = data.payload || [];
  } catch (failure) {
    if (request === listGeneration && !handleSensitiveError(failure))
      useAlert(label('FAILED'));
  } finally {
    if (request === listGeneration) loading.value = false;
  }
};

// 成员列表：供「关联系统账号」与离职交接接手人选择。
const agents = ref([]);
const fetchAgents = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/agents`
    );
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
};

const fetchDepartments = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/org/departments`
    );
    departments.value = data.payload || [];
  } catch {
    departments.value = [];
  }
};

// ── 敏感区二次验证：先输登录密码解锁（15 分钟免验），解锁后才拉数据 ──
// ── 敏感字段脱敏：身份证/银行卡默认打码，点「显示」才展开明文并可编辑 ──
const showIdCard = ref(false);
const showBankCard = ref(false);
const masked = v => {
  if (!v) return '—';
  const text = String(v);
  if (text.length <= 8) return '*'.repeat(text.length);
  return `${text.slice(0, 4)}${'*'.repeat(text.length - 8)}${text.slice(-4)}`;
};

const historyOpen = ref(false);
const historyRows = ref([]);
const historyLoading = ref(false);

// ── 表单下拉选项（紫玻璃 SelectCard）──
const genderOptions = computed(() => [
  { value: '', label: '选择性别' },
  ...GENDER.map(([value, text]) => ({ value, label: text })),
]);
const departmentOptions = computed(() => [
  { value: '', label: '选择部门' },
  ...departments.value.map(d => ({ value: String(d.id), label: d.name })),
]);
const userOptions = computed(() => [
  { value: '', label: '未关联（离职交接需要）' },
  ...agents.value.map(a => ({
    value: String(a.id),
    label: `${a.name}（${a.email}）`,
  })),
]);
const statusOptions = computed(() =>
  STATUS.map(([value, text]) => ({ value, label: text }))
);
const contractTypeOptions = computed(() => [
  { value: '', label: '选择合同类型' },
  ...CONTRACT_TYPE.map(([value, text]) => ({ value, label: text })),
]);
const handoverTargetOptions = computed(() => [
  { value: '', label: '选择接手人' },
  ...agents.value
    .filter(x => String(x.id) !== form.userId)
    .map(a => ({ value: String(a.id), label: a.name })),
]);
const resignTypeOptions = computed(() => [
  { value: '', label: '选择离职类型' },
  ...RESIGN_TYPE.map(([value, text]) => ({ value, label: text })),
]);

const filtered = computed(() => {
  const kw = q.value.trim().toLowerCase();
  return employees.value.filter(
    e =>
      (!tab.value || e.status === tab.value) &&
      (!kw ||
        `${e.name} ${e.employee_no} ${e.phone || ''}`
          .toLowerCase()
          .includes(kw))
  );
});
const countOf = s => employees.value.filter(e => !s || e.status === s).length;

// 工龄：入职日期起算，离职员工算到离职日，其余算到今天。
const seniority = row => {
  if (!row.hire_date) return '—';
  const start = new Date(row.hire_date);
  const end =
    row.status === 'RESIGNED' && row.resign_date
      ? new Date(row.resign_date)
      : new Date();
  let months =
    (end.getFullYear() - start.getFullYear()) * 12 +
    (end.getMonth() - start.getMonth());
  if (end.getDate() < start.getDate()) months -= 1;
  if (months < 0) return '—';
  const y = Math.floor(months / 12);
  const m = months % 12;
  return y ? `${y}年${m}个月` : `${m}个月`;
};

const fmtBytes = n => {
  if (!n) return '';
  if (n < 1024) return `${n} B`;
  if (n < 1_048_576) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1_048_576).toFixed(1)} MB`;
};

const resetForm = () => {
  Object.assign(form, {
    employeeNo: '',
    name: '',
    gender: '',
    idCardNo: '',
    birthDate: '',
    nativePlace: '',
    departmentId: '',
    userId: '',
    jobTitle: '',
    jobCategory: '',
    workLocation: '',
    status: 'PROBATION',
    hireDate: '',
    regularDate: '',
    probationMonths: '',
    contractStartDate: '',
    contractEndDate: '',
    contractType: '',
    renewCount: '',
    salaryNote: '',
    bankCardNo: '',
    bankName: '',
    phone: '',
    email: '',
    wechat: '',
    resignDate: '',
    resignReason: '',
    resignType: '',
    handoverMode: 'pool',
    handoverTargetId: '',
  });
  photoUrl.value = null;
  entryFiles.value = [];
  resignFiles.value = [];
  pendingPhoto.value = null;
  if (pendingPhotoPreview.value) URL.revokeObjectURL(pendingPhotoPreview.value);
  pendingPhotoPreview.value = null;
  pendingEntry.value = [];
  pendingResign.value = [];
  showIdCard.value = false;
  showBankCard.value = false;
  historyOpen.value = false;
  historyRows.value = [];
  errorMsg.value = '';
  fileBusy.value = false;
  historyLoading.value = false;
  canOffboard.value = false;
  uploadTasks.value = [];
  persistedSignature.value = '';
  pendingHandoverRetry.value = false;
};

const trimmed = v => (v && v.trim ? v.trim() : v) || null;
const num = v => (v === '' || v === null || v === undefined ? null : Number(v));

const buildPayload = () => ({
  employee_no: form.employeeNo.trim(),
  name: form.name.trim(),
  gender: form.gender || null,
  id_card_no: trimmed(form.idCardNo),
  birth_date: form.birthDate || null,
  native_place: trimmed(form.nativePlace),
  department_id: form.departmentId || null,
  user_id: form.userId || null,
  job_title: trimmed(form.jobTitle),
  job_category: trimmed(form.jobCategory),
  work_location: trimmed(form.workLocation),
  status: form.status,
  hire_date: form.hireDate || null,
  regular_date: form.regularDate || null,
  probation_months: num(form.probationMonths),
  contract_start_date: form.contractStartDate || null,
  contract_end_date: form.contractEndDate || null,
  contract_type: form.contractType || null,
  renew_count: form.contractType === 'RENEWAL' ? num(form.renewCount) : null,
  salary_note: trimmed(form.salaryNote),
  bank_card_no: trimmed(form.bankCardNo),
  bank_name: trimmed(form.bankName),
  phone: trimmed(form.phone),
  email: trimmed(form.email),
  wechat: trimmed(form.wechat),
  resign_date: form.status === 'RESIGNED' ? form.resignDate || null : null,
  resign_reason: form.status === 'RESIGNED' ? trimmed(form.resignReason) : null,
  resign_type: form.status === 'RESIGNED' ? form.resignType || null : null,
});

const openCreate = () => {
  if (!mayDiscard()) return;
  formGeneration += 1;
  resetForm();
  showIdCard.value = true;
  showBankCard.value = true;
  editingId.value = null;
  mode.value = 'form';
  saving.value = false;
  detailLoading.value = false;
  markPristine();
};

const openEdit = async row => {
  if (!mayDiscard()) return;
  formGeneration += 1;
  const request = formGeneration;
  resetForm();
  editingId.value = null;
  detailLoading.value = true;
  saving.value = false;
  mode.value = 'list';
  let rec;
  try {
    const { data } = await axios.get(`${api()}/${row.id}`);
    if (request !== formGeneration) return;
    rec = data;
  } catch (failure) {
    if (request === formGeneration && !handleSensitiveError(failure))
      useAlert(failure?.response?.data?.error || label('EMPLOYEE_NOT_FOUND'));
    return;
  } finally {
    if (request === formGeneration) detailLoading.value = false;
  }
  editingId.value = rec.id;
  canOffboard.value = rec.can_offboard === true;
  Object.assign(form, {
    employeeNo: rec.employee_no || '',
    name: rec.name || '',
    gender: rec.gender || '',
    idCardNo: rec.id_card_no || '',
    birthDate: rec.birth_date || '',
    nativePlace: rec.native_place || '',
    departmentId: rec.department_id ? String(rec.department_id) : '',
    userId: rec.user_id ? String(rec.user_id) : '',
    jobTitle: rec.job_title || '',
    jobCategory: rec.job_category || '',
    workLocation: rec.work_location || '',
    status: rec.status || 'PROBATION',
    hireDate: rec.hire_date || '',
    regularDate: rec.regular_date || '',
    probationMonths: rec.probation_months ?? '',
    contractStartDate: rec.contract_start_date || '',
    contractEndDate: rec.contract_end_date || '',
    contractType: rec.contract_type || '',
    renewCount: rec.renew_count ?? '',
    salaryNote: rec.salary_note || '',
    bankCardNo: rec.bank_card_no || '',
    bankName: rec.bank_name || '',
    phone: rec.phone || '',
    email: rec.email || '',
    wechat: rec.wechat || '',
    resignDate: rec.resign_date || '',
    resignReason: rec.resign_reason || '',
    resignType: rec.resign_type || '',
  });
  photoUrl.value = rec.photo_url || null;
  entryFiles.value = rec.entry_files || [];
  resignFiles.value = rec.resign_files || [];
  mode.value = 'form';
  persistedSignature.value = JSON.stringify(buildPayload());
  markPristine();
};

// ── 操作历史：变更审计 + 查看记录时间轴（编辑态展开加载）──
const FIELD_LABELS = {
  employee_no: '工号',
  name: '姓名',
  gender: '性别',
  id_card_no: '身份证号',
  birth_date: '出生日期',
  native_place: '籍贯',
  department_id: '所属部门',
  user_id: '关联账号',
  job_title: '岗位名称',
  job_category: '岗位类别',
  work_location: '工作地点',
  status: '员工状态',
  hire_date: '入职日期',
  regular_date: '转正日期',
  probation_months: '试用期',
  contract_start_date: '合同开始',
  contract_end_date: '合同结束',
  contract_type: '合同类型',
  renew_count: '续签次数',
  salary_note: '薪资标准',
  bank_card_no: '银行卡号',
  bank_name: '开户行',
  phone: '手机号',
  email: '邮箱',
  wechat: '微信',
  resign_date: '离职日期',
  resign_reason: '离职原因',
  resign_type: '离职类型',
};
const historyText = r => {
  if (r.kind === 'workflow') return label(r.action.toUpperCase());
  if (r.kind === 'view') return '查看了档案';
  if (r.action === 'create') return '创建了档案';
  const fields = (r.changed_fields || [])
    .map(f => FIELD_LABELS[f] || f)
    .join('、');
  return fields ? `修改了 ${fields}` : '更新了档案';
};
const toggleHistory = async () => {
  historyOpen.value = !historyOpen.value;
  if (!historyOpen.value || historyRows.value.length) return;
  historyGeneration += 1;
  const request = historyGeneration;
  const owner = editingId.value;
  historyLoading.value = true;
  try {
    const { data } = await axios.get(`${api()}/${editingId.value}/audits`);
    if (request === historyGeneration && owner === editingId.value)
      historyRows.value = data.payload || [];
  } catch (failure) {
    if (owner === editingId.value && !handleSensitiveError(failure))
      useAlert(label('FAILED'));
  } finally {
    if (request === historyGeneration) historyLoading.value = false;
  }
};

const backToList = (force = false) => {
  if (force !== true && !mayDiscard()) return;
  formGeneration += 1;
  historyGeneration += 1;
  mode.value = 'list';
  editingId.value = null;
  resetForm();
  saving.value = false;
  markPristine();
};

const missing = computed(() => {
  const m = [];
  if (!form.employeeNo.trim()) m.push('员工工号');
  if (!form.name.trim()) m.push('姓名');
  return m;
});

// ── 附件 ──
const pickPhoto = e => {
  const file = e.target.files?.[0];
  if (!file) return;
  pendingPhoto.value = file;
  if (pendingPhotoPreview.value) URL.revokeObjectURL(pendingPhotoPreview.value);
  pendingPhotoPreview.value = URL.createObjectURL(file);
  e.target.value = '';
};

const pickFiles = (kind, e) => {
  const files = Array.from(e.target.files || []);
  if (!files.length) return;
  if (kind === 'entry') pendingEntry.value.push(...files);
  else pendingResign.value.push(...files);
  e.target.value = '';
};

const dropPending = (kind, idx) => {
  if (kind === 'entry') pendingEntry.value.splice(idx, 1);
  else pendingResign.value.splice(idx, 1);
};

const sendFiles = (id, task) => {
  const fd = new FormData();
  fd.append('kind', task.kind);
  fd.append('upload_key', task.key);
  fd.append('files[]', task.file);
  return axios.post(`${api()}/${id}/attach`, fd);
};
const updateFiles = data => {
  photoUrl.value = data.photo_url || null;
  entryFiles.value = data.entry_files || [];
  resignFiles.value = data.resign_files || [];
};
const uploadPending = async (id, tasks, request) => {
  // Keep uploads sequential so a failure leaves each remaining file retryable.
  // eslint-disable-next-line no-restricted-syntax
  for (const task of tasks) {
    if (request !== formGeneration) return;
    task.status = 'running';
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await sendFiles(id, task);
      if (request !== formGeneration) return;
      task.status = 'done';
      updateFiles(data);
      if (task.kind === 'photo') {
        if (pendingPhoto.value === task.file) {
          pendingPhoto.value = null;
          if (pendingPhotoPreview.value)
            URL.revokeObjectURL(pendingPhotoPreview.value);
          pendingPhotoPreview.value = null;
        }
      } else if (task.kind === 'entry')
        pendingEntry.value = pendingEntry.value.filter(
          file => file !== task.file
        );
      else
        pendingResign.value = pendingResign.value.filter(
          file => file !== task.file
        );
    } catch (failure) {
      task.status = 'failed';
      throw failure;
    }
  }
};
const removeFile = async fileId => {
  if (!editingId.value || fileBusy.value || saving.value) return;
  const owner = editingId.value;
  const request = formGeneration;
  fileBusy.value = true;
  try {
    const { data } = await axios.delete(`${api()}/${owner}/attach/${fileId}`);
    if (request === formGeneration && owner === editingId.value)
      updateFiles(data);
  } catch (failure) {
    if (request === formGeneration && !handleSensitiveError(failure))
      errorMsg.value = failure?.response?.data?.error || label('FAILED');
  } finally {
    if (request === formGeneration) fileBusy.value = false;
  }
};
const restoreFile = async event => {
  if (fileBusy.value || saving.value) return;
  const owner = editingId.value;
  const request = formGeneration;
  fileBusy.value = true;
  try {
    const { data } = await axios.post(`${api()}/${owner}/restore_file`, {
      event_id: event.id,
    });
    if (request === formGeneration && owner === editingId.value) {
      updateFiles(data);
      historyRows.value = [];
      historyOpen.value = false;
      await toggleHistory();
    }
  } catch (failure) {
    if (request === formGeneration && !handleSensitiveError(failure))
      useAlert(failure?.response?.data?.error || label('FAILED'));
  } finally {
    if (request === formGeneration) fileBusy.value = false;
  }
};
const retryFromWorkbench = async row => {
  await openEdit(row);
  if (editingId.value !== row.id || !canOffboard.value) return;
  pendingHandoverRetry.value = true;
  form.status = 'RESIGNED';
  form.handoverMode = row.mode || 'pool';
  form.handoverTargetId = row.target_user_id ? String(row.target_user_id) : '';
};
const previewHandover = async () => {
  const owner = editingId.value;
  const request = formGeneration;
  if (!owner || !form.userId || !canOffboard.value) return;
  try {
    const { data } = await axios.get(`${api()}/${owner}/offboarding_preview`, {
      params: {
        handover_mode: form.handoverMode,
        handover_target_id: form.handoverTargetId || null,
      },
    });
    if (request === formGeneration)
      useAlert(t('CRM.HR_WORKFLOW.HANDOVER_COUNTS', data));
  } catch (failure) {
    if (request === formGeneration && !handleSensitiveError(failure))
      useAlert(failure?.response?.data?.error || label('FAILED'));
  }
};
const save = async () => {
  if (
    missing.value.length ||
    saving.value ||
    detailLoading.value ||
    fileBusy.value
  )
    return;
  const request = formGeneration;
  const payload = buildPayload();
  const signature = JSON.stringify(payload);
  if (
    payload.status === 'RESIGNED' &&
    payload.user_id &&
    (persistedSignature.value !== signature || pendingHandoverRetry.value) &&
    !window.confirm(label('HANDOVER_CONFIRM'))
  )
    return;
  const handover = {
    handover_mode: form.handoverMode,
    handover_target_id:
      form.handoverMode === 'transfer' ? form.handoverTargetId || null : null,
  };
  const tasks = [
    ...(pendingPhoto.value
      ? [{ kind: 'photo', file: pendingPhoto.value }]
      : []),
    ...pendingEntry.value.map(file => ({ kind: 'entry', file })),
    ...pendingResign.value.map(file => ({ kind: 'resign', file })),
  ].map(task => ({ ...task, key: uploadKey(task.file), status: 'pending' }));
  uploadTasks.value = tasks;
  saving.value = true;
  errorMsg.value = '';
  try {
    let id = editingId.value;
    if (
      !id ||
      persistedSignature.value !== signature ||
      pendingHandoverRetry.value
    ) {
      const response = id
        ? await axios.patch(`${api()}/${id}`, {
            employee: payload,
            ...handover,
          })
        : await axios.post(api(), { employee: payload });
      id = response.data.id;
      if (request !== formGeneration) return;
      editingId.value = id;
      canOffboard.value = response.data.can_offboard === true;
      persistedSignature.value = signature;
      pendingHandoverRetry.value = false;
    }
    await uploadPending(id, uploadTasks.value, request);
    if (request !== formGeneration) return;
    workbenchRefresh.value += 1;
    markPristine();
    await fetchList();
    if (request === formGeneration) {
      useAlert(label('SAVED'));
      backToList(true);
    }
  } catch (failure) {
    if (request === formGeneration && !handleSensitiveError(failure))
      errorMsg.value =
        failure?.response?.data?.message ||
        failure?.response?.data?.error ||
        label('UPLOAD_FAILED');
  } finally {
    if (request === formGeneration) saving.value = false;
  }
};

const removeEmployee = async row => {
  if (pendingDeleteId.value !== row.id) {
    pendingDeleteId.value = row.id;
    return;
  }
  pendingDeleteId.value = null;
  try {
    await axios.delete(`${api()}/${row.id}`);
    employees.value = employees.value.filter(e => e.id !== row.id);
  } catch (failure) {
    if (!handleSensitiveError(failure))
      useAlert(failure?.response?.data?.error || label('FAILED'));
  }
};
const loadAll = async () => {
  await Promise.all([fetchList(), fetchDepartments(), fetchAgents()]);
  if (route.query.focus && mode.value === 'list' && sudoActive.value)
    openEdit({ id: route.query.focus });
};
watch(
  sudoActive,
  unlocked => {
    if (unlocked) loadAll();
    else {
      formGeneration += 1;
      listGeneration += 1;
      historyGeneration += 1;
      employees.value = [];
      editingId.value = null;
      mode.value = 'list';
      resetForm();
      saving.value = false;
      markPristine();
    }
  },
  { flush: 'sync', immediate: true }
);
onBeforeRouteLeave(() => mayDiscard());
onMounted(() => {
  if (route.query.focus && sudoActive.value)
    openEdit({ id: route.query.focus });
});
onBeforeUnmount(() => {
  formGeneration += 1;
  listGeneration += 1;
  historyGeneration += 1;
  if (pendingPhotoPreview.value) URL.revokeObjectURL(pendingPhotoPreview.value);
});
</script>

<template>
  <HScrollButtons />
  <div
    class="flex flex-col w-full h-full overflow-auto backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-2 px-4 py-3 border-b sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <h1 class="text-n-slate-12 text-heading-1">
        {{ mode === 'list' ? '员工档案' : editingId ? '编辑员工' : '新增员工' }}
      </h1>
      <button
        v-if="sudoActive && mode === 'list'"
        class="h-9 px-4 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
        @click="openCreate"
      >
        {{ label('EMPLOYEE.ADD_EMPLOYEE') }}
      </button>
      <button
        v-else-if="sudoActive"
        class="h-9 px-4 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="backToList"
      >
        {{ label('EMPLOYEE.BACK') }}
      </button>
    </div>

    <div v-if="sudoActive && mode === 'list'" class="px-4 pt-4 sm:px-6">
      <HrWorkbench
        :active="sudoActive"
        :refresh-key="workbenchRefresh"
        @open="openEdit"
        @retry="retryFromWorkbench"
      />
    </div>
    <p v-if="detailLoading" role="status" class="p-4 text-label-small">
      {{ label('LOADING') }}
    </p>
    <!-- ── 敏感区解锁门：二次密码验证，15 分钟免验 ── -->
    <div
      v-if="!sudoActive"
      class="flex flex-col items-center justify-center gap-3 px-6 py-24 [.theme-classic_&]:!px-4 [.theme-classic_&]:sm:!px-8"
    >
      <span class="i-lucide-shield-check size-9 text-n-iris-9" />
      <p class="text-sm font-medium text-n-slate-12">
        {{ label('EMPLOYEE.SENSITIVE_NOTICE') }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{ label('EMPLOYEE.SENSITIVE_HELP') }}
      </p>
      <div v-if="!sudoChecking" class="flex items-center gap-2 mt-1">
        <input
          v-model="sudoPassword"
          type="password"
          class="h-9 px-3 text-sm border rounded-lg w-56 border-n-weak bg-n-solid-1 text-n-slate-12"
          :placeholder="label('EMPLOYEE.PASSWORD')"
          @keyup.enter="unlock"
        />
        <button
          class="h-9 px-4 shrink-0 whitespace-nowrap disabled:opacity-50 text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 transition-colors duration-150"
          :disabled="!sudoPassword || sudoVerifying"
          @click="unlock"
        >
          {{ sudoVerifying ? '验证中…' : '解锁' }}
        </button>
      </div>
      <span v-if="sudoError" class="text-xs text-n-ruby-11">
        {{ sudoError }}
      </span>
    </div>

    <!-- ── 列表视图 ── -->
    <div
      v-else-if="mode === 'list'"
      class="flex flex-col gap-4 px-4 py-4 sm:px-6 sm:py-5 [.theme-classic_&]:sm:!px-8"
    >
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="[val, lab] in TABS"
          :key="val"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            tab === val
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="tab = val"
        >
          {{ lab }}{{ label('EMPLOYEE.OPEN_PAREN') }}{{ countOf(val)
          }}{{ label('EMPLOYEE.CLOSE_PAREN') }}
        </button>
        <input
          v-model="q"
          class="h-8 px-3 text-sm border rounded-lg w-full sm:ml-auto sm:w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          :placeholder="label('EMPLOYEE.SEARCH')"
        />
      </div>

      <!-- ── 手机卡片列表 ── -->
      <div class="flex flex-col gap-2 md:hidden">
        <div v-if="loading" class="py-6 text-sm text-center text-n-slate-11">
          {{ label('EMPLOYEE.LOADING') }}
        </div>
        <div
          v-else-if="!filtered.length"
          class="py-6 text-sm text-center text-n-slate-11"
        >
          {{ label('EMPLOYEE.EMPTY') }}
        </div>
        <template v-else>
          <div
            v-for="row in filtered"
            :key="`card-${row.id}`"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
            @click="openEdit(row)"
          >
            <div class="flex items-center gap-2">
              <img
                v-if="row.photo_url"
                :src="row.photo_url"
                class="object-cover w-6 h-6 rounded-full shrink-0"
              />
              <span class="font-medium truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <span
                class="px-2 py-0.5 shrink-0 text-label-small rounded-full"
                :class="STATUS_STYLE[row.status]"
              >
                {{ STATUS_LABEL[row.status] || row.status }}
              </span>
              <span class="flex-1" />
              <div class="shrink-0" @click.stop>
                <button
                  class="px-2 text-xs text-n-iris-11 hover:underline"
                  @click="openEdit(row)"
                >
                  {{ label('EMPLOYEE.EDIT') }}
                </button>
                <button
                  class="px-2 text-xs hover:underline"
                  :class="
                    pendingDeleteId === row.id
                      ? 'text-n-ruby-11 font-medium'
                      : 'text-n-slate-11'
                  "
                  @click="removeEmployee(row)"
                >
                  {{ pendingDeleteId === row.id ? '确认删除' : '删除' }}
                </button>
              </div>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-1.5 text-xs text-n-slate-11"
            >
              <span
                >{{ label('EMPLOYEE.EMPLOYEE_NO_PREFIX')
                }}{{ row.employee_no }}</span
              >
              <span
                >{{ label('EMPLOYEE.GENDER_PREFIX')
                }}{{ GENDER_LABEL[row.gender] || '—' }}</span
              >
              <span
                >{{ label('EMPLOYEE.DEPARTMENT_PREFIX')
                }}{{ row.department_name || '—' }}</span
              >
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-1 text-xs text-n-slate-11"
            >
              <span
                >{{ label('EMPLOYEE.JOB_PREFIX')
                }}{{ row.job_title || '—' }}</span
              >
              <span
                >{{ label('EMPLOYEE.HIRE_PREFIX')
                }}{{ row.hire_date || '—' }}</span
              >
              <span
                >{{ label('EMPLOYEE.TENURE_PREFIX') }}{{ seniority(row) }}</span
              >
            </div>
            <div class="mt-1 text-xs text-n-slate-11">
              {{ label('EMPLOYEE.PHONE_PREFIX') }}{{ row.phone || '—' }}
            </div>
          </div>
        </template>
      </div>

      <HScrollButtons />
      <div
        class="hidden overflow-x-auto border md:block rounded-xl border-n-weak"
      >
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.EMPLOYEE_NO') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.NAME') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.GENDER') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.DEPARTMENT') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.JOB') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.STATUS') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.HIRE_DATE') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.TENURE') }}
              </th>
              <th class="px-3 py-2 font-medium whitespace-nowrap">
                {{ label('EMPLOYEE.PHONE') }}
              </th>
              <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
                {{ label('EMPLOYEE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="10" class="px-3 py-6 text-center text-n-slate-11">
                {{ label('EMPLOYEE.LOADING') }}
              </td>
            </tr>
            <tr v-else-if="!filtered.length">
              <td colspan="10" class="px-3 py-6 text-center text-n-slate-11">
                {{ label('EMPLOYEE.EMPTY') }}
              </td>
            </tr>
            <tr
              v-for="row in filtered"
              :key="row.id"
              class="border-b cursor-pointer border-n-weak/60 text-n-slate-12 hover:bg-n-alpha-1"
              @click="openEdit(row)"
            >
              <td class="px-3 py-2 whitespace-nowrap">{{ row.employee_no }}</td>
              <td class="px-3 py-2 whitespace-nowrap">
                <span class="inline-flex items-center gap-2">
                  <img
                    v-if="row.photo_url"
                    :src="row.photo_url"
                    class="object-cover w-6 h-6 rounded-full"
                  />
                  {{ row.name }}
                </span>
              </td>
              <td class="px-3 py-2">{{ GENDER_LABEL[row.gender] || '—' }}</td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ row.department_name || '—' }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ row.job_title || '—' }}
              </td>
              <td class="px-3 py-2">
                <span
                  class="px-2 py-0.5 text-label-small rounded-full"
                  :class="STATUS_STYLE[row.status]"
                >
                  {{ STATUS_LABEL[row.status] || row.status }}
                </span>
              </td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ row.hire_date || '—' }}
              </td>
              <td class="px-3 py-2 whitespace-nowrap">{{ seniority(row) }}</td>
              <td class="px-3 py-2 whitespace-nowrap">
                {{ row.phone || '—' }}
              </td>
              <td class="px-3 py-2 text-right whitespace-nowrap" @click.stop>
                <button
                  class="px-2 text-xs text-n-iris-11 hover:underline"
                  @click="openEdit(row)"
                >
                  {{ label('EMPLOYEE.EDIT') }}
                </button>
                <button
                  class="px-2 text-xs hover:underline"
                  :class="
                    pendingDeleteId === row.id
                      ? 'text-n-ruby-11 font-medium'
                      : 'text-n-slate-11'
                  "
                  @click="removeEmployee(row)"
                >
                  {{ pendingDeleteId === row.id ? '确认删除' : '删除' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ── 建档 / 编辑表单 ── -->
    <div
      v-else
      class="flex flex-col w-full max-w-3xl gap-4 px-4 py-4 sm:px-6 sm:py-5 [.theme-classic_&]:sm:!px-8"
    >
      <p class="text-xs text-n-slate-11">
        {{ label('EMPLOYEE.FORM_HINT') }}
        <span class="text-n-ruby-11">{{
          label('EMPLOYEE.REQUIRED_MARK')
        }}</span>
        {{ label('EMPLOYEE.REQUIRED_HINT') }}
      </p>

      <!-- 一、基本身份信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.IDENTITY_SECTION') }}
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >{{ label('EMPLOYEE.EMPLOYEE_NUMBER') }}
            <span class="text-n-ruby-11">{{
              label('EMPLOYEE.REQUIRED_MARK')
            }}</span></span
          >
          <input
            v-model="form.employeeNo"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >{{ label('EMPLOYEE.NAME') }}
            <span class="text-n-ruby-11">{{
              label('EMPLOYEE.REQUIRED_MARK')
            }}</span></span
          >
          <input
            v-model="form.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            :placeholder="label('EMPLOYEE.EMPLOYEE_NAME')"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.GENDER')
          }}</span>
          <SelectCard v-model="form.gender" :options="genderOptions" block />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.ID_CARD')
          }}</span>
          <div class="flex items-center gap-2">
            <input
              v-if="showIdCard"
              v-model="form.idCardNo"
              class="flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              :placeholder="label('EMPLOYEE.ID_CARD_PLACEHOLDER')"
            />
            <span
              v-else
              class="flex items-center flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-11"
            >
              {{ masked(form.idCardNo) }}
            </span>
            <button
              type="button"
              class="text-xs text-n-iris-11 hover:underline"
              @click="showIdCard = !showIdCard"
            >
              {{ showIdCard ? '隐藏' : '显示' }}
            </button>
          </div>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.BIRTH_DATE')
          }}</span>
          <DatePicker v-model="form.birthDate" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.NATIVE_PLACE')
          }}</span>
          <input
            v-model="form.nativePlace"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.PHOTO')
          }}</span>
          <div class="flex items-center gap-3">
            <img
              v-if="pendingPhotoPreview || photoUrl"
              :src="pendingPhotoPreview || photoUrl"
              class="object-cover w-16 h-16 border rounded-lg border-n-weak"
            />
            <label
              class="h-9 px-3 inline-flex items-center border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2 text-label"
            >
              {{ pendingPhotoPreview || photoUrl ? '更换照片' : '上传照片' }}
              <input
                type="file"
                accept="image/*"
                class="hidden"
                @change="pickPhoto"
              />
            </label>
          </div>
        </div>
        <div class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.ENTRY_FILES')
          }}</span>
          <div class="flex flex-col gap-1">
            <div
              v-for="f in entryFiles"
              :key="f.id"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <a
                :href="f.url"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-iris-11 hover:underline"
              >
                {{ f.filename }}
              </a>
              <span class="text-xs text-n-slate-10">{{
                fmtBytes(f.byte_size)
              }}</span>
              <button
                class="text-xs text-n-ruby-11 hover:underline"
                @click="removeFile(f.id)"
              >
                {{ label('EMPLOYEE.DELETE') }}
              </button>
            </div>
            <div
              v-for="(f, i) in pendingEntry"
              :key="`p-${i}`"
              class="flex items-center gap-2 text-sm text-n-slate-11"
            >
              <span>{{ f.name }}</span>
              <span class="text-xs text-n-slate-10">{{
                label('EMPLOYEE.UPLOAD_PENDING')
              }}</span>
              <button
                class="text-xs text-n-ruby-11 hover:underline"
                @click="dropPending('entry', i)"
              >
                {{ label('EMPLOYEE.REMOVE') }}
              </button>
            </div>
            <label
              class="h-9 px-3 inline-flex items-center self-start border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2 text-label"
            >
              {{ label('EMPLOYEE.ADD_ENTRY_FILES') }}
              <input
                type="file"
                multiple
                class="hidden"
                @change="pickFiles('entry', $event)"
              />
            </label>
          </div>
        </div>
      </div>

      <!-- 二、岗位与组织信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.POSITION_SECTION') }}
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.DEPARTMENT_NAME')
          }}</span>
          <SelectCard
            v-model="form.departmentId"
            :options="departmentOptions"
            block
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.LINKED_USER')
          }}</span>
          <SelectCard v-model="form.userId" :options="userOptions" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.JOB_TITLE')
          }}</span>
          <input
            v-model="form.jobTitle"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.JOB_CATEGORY')
          }}</span>
          <input
            v-model="form.jobCategory"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.LOCATION')
          }}</span>
          <input
            v-model="form.workLocation"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
      </div>

      <!-- 三、在职状态与关键日期 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.EMPLOYMENT_SECTION') }}
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.EMPLOYEE_STATUS')
          }}</span>
          <SelectCard v-model="form.status" :options="statusOptions" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.HIRE_DATE')
          }}</span>
          <DatePicker v-model="form.hireDate" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.REGULAR_DATE')
          }}</span>
          <DatePicker v-model="form.regularDate" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.PROBATION_MONTHS')
          }}</span>
          <input
            v-model="form.probationMonths"
            type="number"
            min="0"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.TENURE_CALCULATED')
          }}</span>
          <span
            class="h-9 px-3 inline-flex items-center text-sm border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-11"
          >
            {{
              seniority({
                hire_date: form.hireDate,
                status: form.status,
                resign_date: form.resignDate,
              })
            }}
          </span>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.CONTRACT_TYPE')
          }}</span>
          <SelectCard
            v-model="form.contractType"
            :options="contractTypeOptions"
            block
          />
        </label>
        <label
          v-if="form.contractType === 'RENEWAL'"
          class="flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.RENEW_COUNT')
          }}</span>
          <input
            v-model="form.renewCount"
            type="number"
            min="1"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.CONTRACT_START')
          }}</span>
          <DatePicker v-model="form.contractStartDate" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.CONTRACT_END')
          }}</span>
          <DatePicker v-model="form.contractEndDate" block />
        </label>
      </div>

      <!-- 四、薪酬与发薪 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.PAY_SECTION') }}
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.SALARY_NOTE')
          }}</span>
          <input
            v-model="form.salaryNote"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.BANK_CARD')
          }}</span>
          <div class="flex items-center gap-2">
            <input
              v-if="showBankCard"
              v-model="form.bankCardNo"
              class="flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              :placeholder="label('EMPLOYEE.BANK_CARD_PLACEHOLDER')"
            />
            <span
              v-else
              class="flex items-center flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-11"
            >
              {{ masked(form.bankCardNo) }}
            </span>
            <button
              type="button"
              class="text-xs text-n-iris-11 hover:underline"
              @click="showBankCard = !showBankCard"
            >
              {{ showBankCard ? '隐藏' : '显示' }}
            </button>
          </div>
        </div>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.BANK_NAME')
          }}</span>
          <input
            v-model="form.bankName"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
      </div>

      <!-- 五、联系方式 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.CONTACT_SECTION') }}
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.MOBILE')
          }}</span>
          <input
            v-model="form.phone"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            :placeholder="label('EMPLOYEE.MOBILE_PLACEHOLDER')"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.EMAIL')
          }}</span>
          <input
            v-model="form.email"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            :placeholder="label('EMPLOYEE.EMAIL_PLACEHOLDER')"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            label('EMPLOYEE.WECHAT')
          }}</span>
          <input
            v-model="form.wechat"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            :placeholder="label('EMPLOYEE.WECHAT_ID')"
          />
        </label>
      </div>

      <!-- 六、离职信息：标题常驻；员工状态为「离职」时展开字段填写 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ label('EMPLOYEE.RESIGN_SECTION') }}
      </div>
      <p v-if="form.status !== 'RESIGNED'" class="text-xs text-n-slate-11">
        {{ label('EMPLOYEE.RESIGN_HINT') }}
      </p>
      <template v-if="form.status === 'RESIGNED'">
        <!-- 没关联账号就什么也不会发生，必须说出来：原来这块整个 v-if 掉，
             看着像「存了就会停用」，实际一个账号都没停（用户点名）。 -->
        <p
          v-if="!form.userId"
          class="p-3 text-xs border rounded-lg border-n-amber-8 bg-n-amber-3/30 text-n-slate-12"
        >
          {{ label('EMPLOYEE.UNLINKED_HINT_PREFIX')
          }}<b>{{ label('EMPLOYEE.WILL_NOT') }}</b
          >{{ label('EMPLOYEE.UNLINKED_HINT_SUFFIX') }}
        </p>
        <div
          v-if="form.userId"
          class="flex flex-col gap-2 p-3 text-sm border rounded-lg border-n-amber-8 bg-n-amber-3/30"
        >
          <span class="text-xs font-medium text-n-slate-12">
            {{ label('EMPLOYEE.HANDOVER_HINT_PREFIX')
            }}<b>{{ label('EMPLOYEE.HANDOVER_HINT_SUFFIX') }}</b
            >{{ label('EMPLOYEE.PERIOD') }}
          </span>
          <div class="flex flex-wrap items-center gap-4">
            <label
              class="flex items-center gap-1.5 cursor-pointer text-n-slate-11 text-label"
            >
              <input
                v-model="form.handoverMode"
                type="radio"
                value="pool"
                class="accent-n-iris-9"
              />
              {{ label('EMPLOYEE.RETURN_POOL') }}
            </label>
            <label
              class="flex items-center gap-1.5 cursor-pointer text-n-slate-11 text-label"
            >
              <input
                v-model="form.handoverMode"
                type="radio"
                value="transfer"
                class="accent-n-iris-9"
              />
              {{ label('EMPLOYEE.TRANSFER') }}
            </label>
            <SelectCard
              v-if="form.handoverMode === 'transfer'"
              v-model="form.handoverTargetId"
              :options="handoverTargetOptions"
              block
            />
          </div>
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              label('EMPLOYEE.RESIGN_DATE')
            }}</span>
            <DatePicker v-model="form.resignDate" block />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">{{
              label('EMPLOYEE.RESIGN_TYPE')
            }}</span>
            <SelectCard
              v-model="form.resignType"
              :options="resignTypeOptions"
              block
            />
          </label>
          <label class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">{{
              label('EMPLOYEE.RESIGN_REASON')
            }}</span>
            <textarea
              v-model="form.resignReason"
              rows="3"
              class="px-3 py-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              :placeholder="label('EMPLOYEE.RESIGN_REASON_PLACEHOLDER')"
            />
          </label>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">{{
              label('EMPLOYEE.RESIGN_FILES')
            }}</span>
            <div class="flex flex-col gap-1">
              <div
                v-for="f in resignFiles"
                :key="f.id"
                class="flex items-center gap-2 text-sm text-n-slate-12"
              >
                <a
                  :href="f.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-n-iris-11 hover:underline"
                >
                  {{ f.filename }}
                </a>
                <span class="text-xs text-n-slate-10">{{
                  fmtBytes(f.byte_size)
                }}</span>
                <button
                  class="text-xs text-n-ruby-11 hover:underline"
                  @click="removeFile(f.id)"
                >
                  {{ label('EMPLOYEE.DELETE') }}
                </button>
              </div>
              <div
                v-for="(f, i) in pendingResign"
                :key="`p-${i}`"
                class="flex items-center gap-2 text-sm text-n-slate-11"
              >
                <span>{{ f.name }}</span>
                <span class="text-xs text-n-slate-10">{{
                  label('EMPLOYEE.UPLOAD_PENDING')
                }}</span>
                <button
                  class="text-xs text-n-ruby-11 hover:underline"
                  @click="dropPending('resign', i)"
                >
                  {{ label('EMPLOYEE.REMOVE') }}
                </button>
              </div>
              <label
                class="h-9 px-3 inline-flex items-center self-start border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2 text-label"
              >
                {{ label('EMPLOYEE.ADD_RESIGN_FILES') }}
                <input
                  type="file"
                  multiple
                  class="hidden"
                  @change="pickFiles('resign', $event)"
                />
              </label>
            </div>
          </div>
        </div>
      </template>

      <template v-if="editingId">
        <div
          class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
        >
          {{ label('EMPLOYEE.HISTORY') }}
          <button
            type="button"
            class="ml-2 normal-case text-n-iris-11 hover:underline"
            @click="toggleHistory"
          >
            {{ historyOpen ? '收起' : '展开' }}
          </button>
        </div>
        <div
          v-if="historyOpen"
          class="flex flex-col gap-1 text-xs text-n-slate-11"
        >
          <span v-if="historyLoading">{{ label('EMPLOYEE.LOADING') }}</span>
          <span v-else-if="!historyRows.length">{{
            label('EMPLOYEE.NO_HISTORY')
          }}</span>
          <div v-for="(r, i) in historyRows" :key="i">
            {{ new Date(r.created_at).toLocaleString() }}
            {{ label('EMPLOYEE.SEPARATOR') }} {{ r.user_name }}
            {{ historyText(r) }}
            <p v-if="r.payload?.filenames">
              {{ r.payload.filenames.join('、') }}
            </p>
            <a
              v-for="file in r.files || []"
              :key="file.url"
              :href="file.url"
              target="_blank"
              rel="noopener noreferrer"
              class="block text-n-blue-11"
              >{{ file.filename }}</a
            >
            <button
              v-if="r.restorable"
              :disabled="fileBusy"
              class="text-label-small text-n-blue-11"
              @click="restoreFile(r)"
            >
              {{ label('RESTORE_FILE') }}
            </button>
          </div>
        </div>
      </template>

      <div
        v-if="editingId && form.status === 'RESIGNED' && form.userId"
        class="flex flex-wrap items-center gap-2"
      >
        <button
          v-if="canOffboard"
          class="rounded-xl border border-n-weak px-3 py-2 text-label-small"
          @click="previewHandover"
        >
          {{ label('PREVIEW_HANDOVER') }}
        </button>
        <p v-else class="text-label-small text-n-slate-10">
          {{ label('HANDOVER_ADMIN') }}
        </p>
      </div>
      <div
        v-if="uploadTasks.length"
        class="space-y-1 text-label-small"
        aria-live="polite"
      >
        <p
          v-for="task in uploadTasks"
          :key="task.key"
          :class="
            task.status === 'failed' ? 'text-n-ruby-11' : 'text-n-slate-10'
          "
        >
          {{ task.file.name }} {{ label('EMPLOYEE.SEPARATOR') }}
          {{ label(`UPLOAD_${task.status.toUpperCase()}`) }}
        </p>
      </div>
      <div class="flex items-center gap-3 mt-1">
        <button
          class="h-10 px-6 transition-colors disabled:opacity-50 disabled:cursor-not-allowed text-label rounded-xl bg-wintouch-yellow text-wintouch-ink hover:enabled:bg-wintouch-yellow-hover focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50 duration-150"
          :disabled="missing.length > 0 || saving || detailLoading || fileBusy"
          @click="save"
        >
          {{ saving ? '保存中…' : '保存' }}
        </button>
        <span v-if="missing.length" class="text-xs text-n-slate-11">
          {{ label('EMPLOYEE.REQUIRED_PREFIX') }}{{ missing.join('、') }}
        </span>
        <span v-if="errorMsg" class="text-xs text-n-ruby-11">{{
          errorMsg
        }}</span>
      </div>
    </div>
  </div>
</template>
