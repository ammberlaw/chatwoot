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

onMounted(() => {
  fetchList();
  fetchDepartments();
  fetchAgents();
});

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
  errorMsg.value = '';
};

const openCreate = () => {
  resetForm();
  editingId.value = null;
  mode.value = 'form';
};

const openEdit = row => {
  resetForm();
  editingId.value = row.id;
  Object.assign(form, {
    employeeNo: row.employee_no || '',
    name: row.name || '',
    gender: row.gender || '',
    idCardNo: row.id_card_no || '',
    birthDate: row.birth_date || '',
    nativePlace: row.native_place || '',
    departmentId: row.department_id ? String(row.department_id) : '',
    userId: row.user_id ? String(row.user_id) : '',
    jobTitle: row.job_title || '',
    jobCategory: row.job_category || '',
    workLocation: row.work_location || '',
    status: row.status || 'PROBATION',
    hireDate: row.hire_date || '',
    regularDate: row.regular_date || '',
    probationMonths: row.probation_months ?? '',
    contractStartDate: row.contract_start_date || '',
    contractEndDate: row.contract_end_date || '',
    contractType: row.contract_type || '',
    renewCount: row.renew_count ?? '',
    salaryNote: row.salary_note || '',
    bankCardNo: row.bank_card_no || '',
    bankName: row.bank_name || '',
    phone: row.phone || '',
    email: row.email || '',
    wechat: row.wechat || '',
    resignDate: row.resign_date || '',
    resignReason: row.resign_reason || '',
    resignType: row.resign_type || '',
  });
  photoUrl.value = row.photo_url || null;
  entryFiles.value = row.entry_files || [];
  resignFiles.value = row.resign_files || [];
  mode.value = 'form';
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
        v-if="mode === 'list'"
        class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10"
        @click="openCreate"
      >
        新增员工
      </button>
      <button
        v-else
        class="h-9 px-4 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
        @click="backToList"
      >
        返回列表
      </button>
    </div>

    <!-- ── 列表视图 ── -->
    <div v-if="mode === 'list'" class="flex flex-col gap-4 px-6 py-5">
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
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">身份证号</span>
          <input
            v-model="form.idCardNo"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="18 位身份证号"
          />
        </label>
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
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">银行卡号</span>
          <input
            v-model="form.bankCardNo"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="发薪银行卡号"
          />
        </label>
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
