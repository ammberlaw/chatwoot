<script setup>
/* global axios */
import { ref, reactive, computed, onMounted } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

const { accountId } = useAccount();
const api = () => `/api/v1/accounts/${accountId.value}/crm/employees`;

const STATUS = [
  ['ACTIVE', '在职'],
  ['PROBATION', '试用'],
  ['RESIGNED', '离职'],
];
const STATUS_LABEL = Object.fromEntries(STATUS);
const STATUS_STYLE = {
  ACTIVE: 'bg-n-teal-3 text-n-teal-11',
  PROBATION: 'bg-n-amber-3 text-n-amber-11',
  RESIGNED: 'bg-n-slate-3 text-n-slate-11',
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

const fetchList = async () => {
  loading.value = true;
  try {
    const { data } = await axios.get(api());
    employees.value = data.payload || [];
  } catch {
    employees.value = [];
  } finally {
    loading.value = false;
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
const sudoActive = ref(false);
const sudoChecking = ref(true);
const sudoPassword = ref('');
const sudoError = ref('');
const sudoVerifying = ref(false);
const sudoUrl = () =>
  `/api/v1/accounts/${accountId.value}/crm/sensitive_session`;
const loadAll = () => {
  fetchList();
  fetchDepartments();
  fetchAgents();
};
const checkSudo = async () => {
  try {
    const { data } = await axios.get(sudoUrl());
    sudoActive.value = !!data.active;
  } catch {
    sudoActive.value = false;
  } finally {
    sudoChecking.value = false;
  }
  if (sudoActive.value) loadAll();
};
const unlock = async () => {
  if (!sudoPassword.value || sudoVerifying.value) return;
  sudoVerifying.value = true;
  sudoError.value = '';
  try {
    await axios.post(sudoUrl(), { password: sudoPassword.value });
    sudoActive.value = true;
    sudoPassword.value = '';
    loadAll();
  } catch (e) {
    sudoError.value =
      e.response?.status === 401 ? '密码不正确' : '验证失败，请重试';
  } finally {
    sudoVerifying.value = false;
  }
};

onMounted(checkSudo);

// ── 敏感字段脱敏：身份证/银行卡默认打码，点「显示」才展开明文并可编辑 ──
const showIdCard = ref(false);
const showBankCard = ref(false);
const masked = v => {
  if (!v) return '—';
  const t = String(v);
  if (t.length <= 8) return '*'.repeat(t.length);
  return `${t.slice(0, 4)}${'*'.repeat(t.length - 8)}${t.slice(-4)}`;
};

const historyOpen = ref(false);
const historyRows = ref([]);
const historyLoading = ref(false);

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
  pendingPhotoPreview.value = null;
  pendingEntry.value = [];
  pendingResign.value = [];
  showIdCard.value = false;
  showBankCard.value = false;
  historyOpen.value = false;
  historyRows.value = [];
  errorMsg.value = '';
};

const openCreate = () => {
  resetForm();
  showIdCard.value = true;
  showBankCard.value = true;
  editingId.value = null;
  mode.value = 'form';
};

const openEdit = async row => {
  resetForm();
  editingId.value = row.id;
  // 单条查看走 show 接口：服务端记录「谁查看了谁的档案」，并取最新数据。
  let rec = row;
  try {
    const { data } = await axios.get(`${api()}/${rec.id}`);
    rec = data;
  } catch {
    // 拉取失败时退回列表快照
  }
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
  historyLoading.value = true;
  try {
    const { data } = await axios.get(`${api()}/${editingId.value}/audits`);
    historyRows.value = data.payload || [];
  } catch {
    historyRows.value = [];
  } finally {
    historyLoading.value = false;
  }
};

const backToList = () => {
  mode.value = 'list';
  editingId.value = null;
};

const missing = computed(() => {
  const m = [];
  if (!form.employeeNo.trim()) m.push('员工工号');
  if (!form.name.trim()) m.push('姓名');
  return m;
});

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

// ── 附件 ──
const pickPhoto = e => {
  const file = e.target.files?.[0];
  if (!file) return;
  pendingPhoto.value = file;
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

const sendFiles = (id, kind, files) => {
  const fd = new FormData();
  fd.append('kind', kind);
  files.forEach(f => fd.append('files[]', f));
  return axios.post(`${api()}/${id}/attach`, fd, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};

const uploadPending = async id => {
  if (pendingPhoto.value) await sendFiles(id, 'photo', [pendingPhoto.value]);
  if (pendingEntry.value.length)
    await sendFiles(id, 'entry', pendingEntry.value);
  if (pendingResign.value.length)
    await sendFiles(id, 'resign', pendingResign.value);
};

const removeFile = async fileId => {
  if (!editingId.value) return;
  try {
    const { data } = await axios.delete(
      `${api()}/${editingId.value}/attach/${fileId}`
    );
    photoUrl.value = data.photo_url || null;
    entryFiles.value = data.entry_files || [];
    resignFiles.value = data.resign_files || [];
  } catch {
    errorMsg.value = '附件删除失败';
  }
};

const save = async () => {
  if (missing.value.length || saving.value) return;
  saving.value = true;
  errorMsg.value = '';
  try {
    let id = editingId.value;
    if (id) {
      await axios.patch(`${api()}/${id}`, {
        employee: buildPayload(),
        // 状态改为「离职」时后端据此执行交接（退公海/转移）；其他更新忽略。
        handover_mode: form.handoverMode,
        handover_target_id:
          form.handoverMode === 'transfer'
            ? form.handoverTargetId || null
            : null,
      });
    } else {
      const { data } = await axios.post(api(), { employee: buildPayload() });
      id = data.id;
    }
    await uploadPending(id);
    await fetchList();
    backToList();
  } catch (e) {
    errorMsg.value =
      e.response?.data?.message || e.response?.data?.error || '保存失败';
  } finally {
    saving.value = false;
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
  } catch {
    // 删除失败保持列表不变
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ mode === 'list' ? '员工档案' : editingId ? '编辑员工' : '新增员工' }}
      </h1>
      <button
        v-if="sudoActive && mode === 'list'"
        class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10"
        @click="openCreate"
      >
        新增员工
      </button>
      <button
        v-else-if="sudoActive"
        class="h-9 px-4 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="backToList"
      >
        返回列表
      </button>
    </div>

    <!-- ── 敏感区解锁门：二次密码验证，15 分钟免验 ── -->
    <div
      v-if="!sudoActive"
      class="flex flex-col items-center justify-center gap-3 px-6 py-24"
    >
      <span class="i-lucide-shield-check size-9 text-n-iris-9" />
      <p class="text-sm font-medium text-n-slate-12">
        员工档案含身份证、薪酬等敏感信息
      </p>
      <p class="text-xs text-n-slate-11">
        请输入登录密码完成二次验证（15 分钟内免验）；所有查看与修改将留痕。
      </p>
      <div v-if="!sudoChecking" class="flex items-center gap-2 mt-1">
        <input
          v-model="sudoPassword"
          type="password"
          class="h-9 px-3 text-sm border rounded-lg w-56 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="登录密码"
          @keyup.enter="unlock"
        />
        <button
          class="h-9 px-4 text-sm font-medium text-white rounded-lg shrink-0 whitespace-nowrap bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
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
    <div v-else-if="mode === 'list'" class="flex flex-col gap-4 px-6 py-5">
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
          {{ lab }}（{{ countOf(val) }}）
        </button>
        <input
          v-model="q"
          class="h-8 px-3 ml-auto text-sm border rounded-lg w-52 border-n-weak bg-n-solid-1 text-n-slate-12"
          placeholder="搜索姓名 / 工号 / 手机号"
        />
      </div>

      <div class="overflow-x-auto border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left border-b text-n-slate-11 border-n-weak">
              <th class="px-3 py-2 font-medium">工号</th>
              <th class="px-3 py-2 font-medium">姓名</th>
              <th class="px-3 py-2 font-medium">性别</th>
              <th class="px-3 py-2 font-medium">部门</th>
              <th class="px-3 py-2 font-medium">岗位</th>
              <th class="px-3 py-2 font-medium">状态</th>
              <th class="px-3 py-2 font-medium">入职日期</th>
              <th class="px-3 py-2 font-medium">工龄</th>
              <th class="px-3 py-2 font-medium">手机号</th>
              <th class="px-3 py-2 font-medium text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="10" class="px-3 py-6 text-center text-n-slate-11">
                加载中…
              </td>
            </tr>
            <tr v-else-if="!filtered.length">
              <td colspan="10" class="px-3 py-6 text-center text-n-slate-11">
                暂无员工档案
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
                  class="px-2 py-0.5 text-xs rounded-full"
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
                  编辑
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
    <div v-else class="flex flex-col w-full max-w-3xl gap-4 px-6 py-5">
      <p class="text-xs text-n-slate-11">
        员工主数据建档。带
        <span class="text-n-ruby-11">*</span>
        为必填；工号在公司内唯一；工龄按入职日期自动计算。
      </p>

      <!-- 一、基本身份信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        一、基本身份信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >员工工号 <span class="text-n-ruby-11">*</span></span
          >
          <input
            v-model="form.employeeNo"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 EMP0001（公司内唯一）"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >姓名 <span class="text-n-ruby-11">*</span></span
          >
          <input
            v-model="form.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="员工姓名"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">性别</span>
          <select
            v-model="form.gender"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择性别</option>
            <option v-for="[val, lab] in GENDER" :key="val" :value="val">
              {{ lab }}
            </option>
          </select>
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">身份证号</span>
          <div class="flex items-center gap-2">
            <input
              v-if="showIdCard"
              v-model="form.idCardNo"
              class="flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              placeholder="18 位身份证号"
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
          <span class="text-xs text-n-slate-11">出生日期</span>
          <input
            v-model="form.birthDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">籍贯</span>
          <input
            v-model="form.nativePlace"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 广东深圳"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">照片（证件照）</span>
          <div class="flex items-center gap-3">
            <img
              v-if="pendingPhotoPreview || photoUrl"
              :src="pendingPhotoPreview || photoUrl"
              class="object-cover w-16 h-16 border rounded-lg border-n-weak"
            />
            <label
              class="h-9 px-3 inline-flex items-center text-sm border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
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
          <span class="text-xs text-n-slate-11">入职资料（附件）</span>
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
                删除
              </button>
            </div>
            <div
              v-for="(f, i) in pendingEntry"
              :key="`p-${i}`"
              class="flex items-center gap-2 text-sm text-n-slate-11"
            >
              <span>{{ f.name }}</span>
              <span class="text-xs text-n-slate-10">待上传</span>
              <button
                class="text-xs text-n-ruby-11 hover:underline"
                @click="dropPending('entry', i)"
              >
                移除
              </button>
            </div>
            <label
              class="h-9 px-3 inline-flex items-center self-start text-sm border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
            >
              添加入职资料
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
        二、岗位与组织信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">所属部门</span>
          <select
            v-model="form.departmentId"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择部门</option>
            <option v-for="d in departments" :key="d.id" :value="String(d.id)">
              {{ d.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">关联系统账号</span>
          <select
            v-model="form.userId"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">未关联（离职交接需要）</option>
            <option v-for="a in agents" :key="a.id" :value="String(a.id)">
              {{ a.name }}（{{ a.email }}）
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">岗位名称</span>
          <input
            v-model="form.jobTitle"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 外贸业务员"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">岗位类别</span>
          <input
            v-model="form.jobCategory"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 销售 / 职能 / 生产"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">工作地点</span>
          <input
            v-model="form.workLocation"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 东莞总部"
          />
        </label>
      </div>

      <!-- 三、在职状态与关键日期 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        三、在职状态与关键日期
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">员工状态</span>
          <select
            v-model="form.status"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option v-for="[val, lab] in STATUS" :key="val" :value="val">
              {{ lab }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">入职日期</span>
          <input
            v-model="form.hireDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">转正日期</span>
          <input
            v-model="form.regularDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">试用期期限（月）</span>
          <input
            v-model="form.probationMonths"
            type="number"
            min="0"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 3"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">工龄（自动计算）</span>
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
          <span class="text-xs text-n-slate-11">合同类型</span>
          <select
            v-model="form.contractType"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择合同类型</option>
            <option v-for="[val, lab] in CONTRACT_TYPE" :key="val" :value="val">
              {{ lab }}
            </option>
          </select>
        </label>
        <label
          v-if="form.contractType === 'RENEWAL'"
          class="flex flex-col gap-1"
        >
          <span class="text-xs text-n-slate-11">续签第几次</span>
          <input
            v-model="form.renewCount"
            type="number"
            min="1"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 1"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">合同开始日期</span>
          <input
            v-model="form.contractStartDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">合同结束日期</span>
          <input
            v-model="form.contractEndDate"
            type="date"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
      </div>

      <!-- 四、薪酬与发薪 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        四、薪酬与发薪
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">薪资标准 / 薪资结构</span>
          <input
            v-model="form.salaryNote"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 底薪 8000 + 绩效 2000 + 提成"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">银行卡号</span>
          <div class="flex items-center gap-2">
            <input
              v-if="showBankCard"
              v-model="form.bankCardNo"
              class="flex-1 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              placeholder="发薪银行卡号"
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
          <span class="text-xs text-n-slate-11">开户行</span>
          <input
            v-model="form.bankName"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如 招商银行深圳分行"
          />
        </label>
      </div>

      <!-- 五、联系方式 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        五、联系方式
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">本人手机号</span>
          <input
            v-model="form.phone"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="11 位手机号"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">邮箱</span>
          <input
            v-model="form.email"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="name@example.com"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">微信</span>
          <input
            v-model="form.wechat"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="微信号"
          />
        </label>
      </div>

      <!-- 六、离职信息：标题常驻；员工状态为「离职」时展开字段填写 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        六、离职信息（离职时填）
      </div>
      <p v-if="form.status !== 'RESIGNED'" class="text-xs text-n-slate-11">
        员工状态选择「离职」后，此处填写离职日期、离职类型、离职原因并上传离职资料。
      </p>
      <template v-if="form.status === 'RESIGNED'">
        <div
          v-if="form.userId"
          class="flex flex-col gap-2 p-3 text-sm border rounded-lg border-n-amber-8 bg-n-amber-3/30"
        >
          <span class="text-xs font-medium text-n-slate-12">
            离职交接（保存后执行）：名下客户与商机按下方选择处理，个人文档进回收站，该账号将不再能进入
            CRM。
          </span>
          <div class="flex flex-wrap items-center gap-4">
            <label
              class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
            >
              <input
                v-model="form.handoverMode"
                type="radio"
                value="pool"
                class="accent-n-iris-9"
              />
              客户退回公海
            </label>
            <label
              class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
            >
              <input
                v-model="form.handoverMode"
                type="radio"
                value="transfer"
                class="accent-n-iris-9"
              />
              转移给指定成员
            </label>
            <select
              v-if="form.handoverMode === 'transfer'"
              v-model="form.handoverTargetId"
              class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option value="">选择接手人</option>
              <option
                v-for="a in agents.filter(x => String(x.id) !== form.userId)"
                :key="a.id"
                :value="String(a.id)"
              >
                {{ a.name }}
              </option>
            </select>
          </div>
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">离职日期</span>
            <input
              v-model="form.resignDate"
              type="date"
              class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-11">离职类型</span>
            <select
              v-model="form.resignType"
              class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            >
              <option value="">选择离职类型</option>
              <option v-for="[val, lab] in RESIGN_TYPE" :key="val" :value="val">
                {{ lab }}
              </option>
            </select>
          </label>
          <label class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">离职原因</span>
            <textarea
              v-model="form.resignReason"
              rows="3"
              class="px-3 py-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
              placeholder="离职原因说明"
            />
          </label>
          <div class="flex flex-col gap-1 sm:col-span-2">
            <span class="text-xs text-n-slate-11">离职资料（附件）</span>
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
                  删除
                </button>
              </div>
              <div
                v-for="(f, i) in pendingResign"
                :key="`p-${i}`"
                class="flex items-center gap-2 text-sm text-n-slate-11"
              >
                <span>{{ f.name }}</span>
                <span class="text-xs text-n-slate-10">待上传</span>
                <button
                  class="text-xs text-n-ruby-11 hover:underline"
                  @click="dropPending('resign', i)"
                >
                  移除
                </button>
              </div>
              <label
                class="h-9 px-3 inline-flex items-center self-start text-sm border rounded-lg cursor-pointer border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
              >
                添加离职资料
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
          操作历史
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
          <span v-if="historyLoading">加载中…</span>
          <span v-else-if="!historyRows.length">暂无记录</span>
          <span v-for="(r, i) in historyRows" :key="i">
            {{ new Date(r.created_at).toLocaleString() }} · {{ r.user_name }}
            {{ historyText(r) }}
          </span>
        </div>
      </template>

      <div class="flex items-center gap-3 mt-1">
        <button
          class="h-10 px-6 text-sm font-medium text-white transition-colors rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="missing.length > 0 || saving"
          @click="save"
        >
          {{ saving ? '保存中…' : '保存' }}
        </button>
        <span v-if="missing.length" class="text-xs text-n-slate-11">
          请填写：{{ missing.join('、') }}
        </span>
        <span v-if="errorMsg" class="text-xs text-n-ruby-11">{{
          errorMsg
        }}</span>
      </div>
    </div>
  </div>
</template>
