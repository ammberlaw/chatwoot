<script setup>
/* global axios */
import { ref, reactive, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import { useDirtyGuard } from 'dashboard/composables/useDirtyGuard';

const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const router = useRouter();
const api = () => `/api/v1/accounts/${accountId.value}/crm/attendances`;

// 从考勤页跳到 OA 审批提交补卡/请假单（compose 参数供审批页预开对应模板）。
const goApproval = kind => {
  router.push({
    name: 'crm_approvals_index',
    params: { accountId: accountId.value },
    query: { compose: kind },
  });
};

// 人事按考勤管理职能与管理员同权：看全员考勤、管理考勤组、改考勤、设打卡网络/地点。
const isAdminLike = computed(
  () =>
    currentUser.value?.role === 'administrator' ||
    currentUser.value?.crm_role === 'deputy_admin' ||
    currentUser.value?.crm_role === 'hr'
);
const isManager = computed(
  () =>
    currentUser.value?.crm_manager === true ||
    currentUser.value?.crm_role === 'manager'
);
const canSummary = computed(() => isAdminLike.value || isManager.value);

const STATUS_META = {
  NORMAL: { label: '正常', cls: 'bg-n-teal-3 text-n-teal-11' },
  LATE: { label: '迟到', cls: 'bg-n-amber-3 text-n-amber-11' },
  EARLY_LEAVE: { label: '早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  LATE_EARLY: { label: '迟到+早退', cls: 'bg-n-amber-3 text-n-amber-11' },
  ABSENT: { label: '旷工', cls: 'bg-n-ruby-3 text-n-ruby-11' },
  LEAVE: { label: '请假', cls: 'bg-n-iris-3 text-n-iris-11' },
  HALF_LEAVE: { label: '请假(半天)', cls: 'bg-n-iris-3 text-n-iris-11' },
  FIELD: { label: '外勤', cls: 'bg-n-blue-3 text-n-blue-11' },
};
const WEEK_LABELS = ['一', '二', '三', '四', '五', '六', '日'];

const statusOptions = computed(() =>
  Object.entries(STATUS_META).map(([k, meta]) => ({
    value: k,
    label: meta.label,
  }))
);

// ── 视图与月份 ──
const view = ref('mine');
const pad = n => String(n).padStart(2, '0');
const todayStr = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const month = ref(todayStr().slice(0, 7));

// ── 我的考勤 ──
const records = ref([]);
const setting = ref(null);
const loadingMine = ref(false);
const fetchMine = async () => {
  loadingMine.value = true;
  try {
    const { data } = await axios.get(api(), {
      params: { month: month.value },
    });
    records.value = data.payload || [];
    setting.value = data.setting;
  } catch {
    records.value = [];
  } finally {
    loadingMine.value = false;
  }
};

const recordByDate = computed(() =>
  Object.fromEntries(records.value.map(r => [r.work_date, r]))
);
const todayRec = computed(() => recordByDate.value[todayStr()] || null);

// 月历：周一开头；过去的工作日无记录 = 旷工
const calendarCells = computed(() => {
  const [y, m] = month.value.split('-').map(Number);
  const lead = (new Date(y, m - 1, 1).getDay() + 6) % 7;
  const days = new Date(y, m, 0).getDate();
  const cells = Array(lead).fill(null);
  for (let d = 1; d <= days; d += 1) cells.push(d);
  return cells;
});
const dayStatus = d => {
  const dateStr = `${month.value}-${pad(d)}`;
  const rec = recordByDate.value[dateStr];
  if (rec) return rec.status;
  if (!setting.value) return null;
  if ((setting.value.holidays || []).includes(dateStr)) return null;
  const dow = new Date(`${dateStr}T12:00:00`).getDay() || 7;
  const isWorkday =
    setting.value.work_days.includes(dow) ||
    (setting.value.extra_workdays || []).includes(dateStr);
  if (!isWorkday) return null;
  return dateStr < todayStr() ? 'ABSENT' : null;
};
const mineCounts = computed(() => {
  const c = {
    present: 0,
    late: 0,
    early: 0,
    absent: 0,
    leave: 0,
    field: 0,
  };
  calendarCells.value.forEach(d => {
    if (!d) return;
    const st = dayStatus(d);
    if (!st) return;
    if (st === 'ABSENT') c.absent += 1;
    else if (st === 'LEAVE') c.leave += 1;
    else if (st === 'HALF_LEAVE') {
      c.present += 0.5;
      c.leave += 0.5;
    } else if (st === 'FIELD') {
      c.present += 1;
      c.field += 1;
    } else {
      c.present += 1;
      if (st === 'LATE' || st === 'LATE_EARLY') c.late += 1;
      if (st === 'EARLY_LEAVE' || st === 'LATE_EARLY') c.early += 1;
    }
  });
  return c;
});

// ── 打卡 ──
const clocking = ref(false);
// 忘打上班卡、过了「上班~下班时段中点」再来打，后端会记成下班卡（见 attendances_controller
// 的 past_workday_midpoint?）。前端按钮必须显示同一口径，否则晚上来补打的人看到的是
// 「上班打卡」，以为下班卡打不了、干脆不点——实际点下去后端记的就是下班。
// 与后端 clock_out_window_start 同一公式：下班前 60 分钟起算「这一下是下班卡」。
// 上下班间隔不足两小时的班次退回中点，避免阈值落到上班时间之前。
const CLOCK_OUT_WINDOW_MINUTES = 60;
const clockOutWindowStart = (i, o) =>
  o - i < CLOCK_OUT_WINDOW_MINUTES * 2
    ? (i + o) / 2
    : o - CLOCK_OUT_WINDOW_MINUTES;

const hm = raw => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(raw || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};
const nowMinutes = () => {
  const d = new Date();
  return d.getHours() * 60 + d.getMinutes();
};
// 这一下会被记成下班卡吗？已有上班卡 → 是；没上班卡但已过中点 → 也是。
const willClockOut = computed(() => {
  if (todayRec.value?.clock_out_at) return false;
  if (todayRec.value?.clock_in_at) return true;
  const i = hm(setting.value?.clock_in_time);
  const o = hm(setting.value?.clock_out_time);
  if (i === null || o === null || o <= i) return false;
  return nowMinutes() >= clockOutWindowStart(i, o);
});

// 现在是否还没到下班时间（用考勤组的下班时间判断，取不到就当已到，不拦）。
const beforeClockOutTime = () => {
  const raw = setting.value?.clock_out_time;
  if (!raw) return false;
  const [h, m] = raw.split(':').map(Number);
  const now = new Date();
  return now.getHours() * 60 + now.getMinutes() < h * 60 + m;
};
// 浏览器取当前定位（考勤组开启 GPS 校验时打卡前调用）。失败/拒绝授权则返回空，交后端判定。
const getGeo = () =>
  new Promise(resolve => {
    if (!navigator.geolocation) {
      resolve({});
      return;
    }
    navigator.geolocation.getCurrentPosition(
      pos => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      () => resolve({}),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
    );
  });
const clock = async (field = false) => {
  if (clocking.value) return;
  // 外勤一键会把当天标记为外勤且用户不可自行撤销，误点代价高，先确认。
  // eslint-disable-next-line no-alert
  if (
    field &&
    !window.confirm('确认外勤打卡？将把今日标记为「外勤」（计出勤、不判迟到）')
  )
    return;
  // 今天已打上班卡、又还没到下班时间时再点，打出来的是下班卡——多半是手滑，先问一句。
  if (
    !field &&
    todayRec.value?.clock_in_at &&
    !todayRec.value?.clock_out_at &&
    beforeClockOutTime()
  ) {
    // eslint-disable-next-line no-alert
    const ok = window.confirm(
      '今天已经打过上班卡了，现在这一下会记成「下班卡」，确定吗？'
    );
    if (!ok) return;
  }
  clocking.value = true;
  try {
    // 组开启 GPS 校验时先取定位；仅网络(IP)校验则无需定位。外勤仍带定位做留痕。
    const body = setting.value?.geo_enabled || field ? await getGeo() : {};
    if (field) body.field = true;
    // 提示按后端实际记录判断：返回记录有下班时间即「下班」，否则「上班」
    // （忘打上班卡、下午来打时后端会智能记为下班，前端据实提示，不再误报「上班」）。
    const { data } = await axios.post(`${api()}/clock`, body);
    if (field) useAlert('外勤打卡成功');
    else useAlert(data?.clock_out_at ? '下班打卡成功' : '上班打卡成功');
    fetchMine();
  } catch (e) {
    useAlert(e.response?.data?.error || '打卡失败，请重试');
  } finally {
    clocking.value = false;
  }
};

// 上班迟到提醒：当前已过「上班时间+宽限」且今天还没打上班卡时，给个预警。
const lateHint = computed(() => {
  if (!setting.value || todayRec.value?.clock_in_at) return null;
  // 已过中点、这一下要记下班卡了，就不是「迟到」的事了，别误导。
  if (willClockOut.value) return null;
  const [h, m] = (setting.value.clock_in_time || '09:00')
    .split(':')
    .map(Number);
  const now = new Date();
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const dueMin = h * 60 + m + (setting.value.grace_minutes || 0);
  const dow = now.getDay() || 7;
  if (!setting.value.work_days.includes(dow)) return null;
  if ((setting.value.holidays || []).includes(todayStr())) return null;
  return nowMin > dueMin
    ? `已超过上班时间 ${nowMin - dueMin} 分钟，现在打卡将记迟到`
    : null;
});

// ── 汇总（日/周/月粒度 + 今日概览）──
const PERIODS = [
  { value: 'day', label: '日' },
  { value: 'week', label: '周' },
  { value: 'month', label: '月' },
];
const period = ref('day');
const summaryDate = ref(todayStr());
const summaryRange = ref(null);
const overview = ref(null);
const summaryRows = ref([]);
const notClockedToday = ref([]);
const summaryGroupId = ref('');
const summaryGroups = ref([]);
const summaryGroupOptions = computed(() => [
  { value: '', label: '全部考勤组' },
  ...summaryGroups.value.map(g => ({ value: String(g.id), label: g.name })),
]);
const loadingSummary = ref(false);
const fetchSummary = async () => {
  loadingSummary.value = true;
  try {
    const { data } = await axios.get(`${api()}/summary`, {
      params: {
        period: period.value,
        date: summaryDate.value,
        group_id: summaryGroupId.value || undefined,
      },
    });
    summaryRows.value = data.payload || [];
    overview.value = data.overview || null;
    summaryRange.value = data.range || null;
    setting.value = data.setting;
    notClockedToday.value = data.not_clocked_today || [];
    summaryGroups.value = data.groups || [];
  } catch (e) {
    summaryRows.value = [];
    overview.value = null;
    useAlert(e.response?.data?.error || '加载考勤汇总失败');
  } finally {
    loadingSummary.value = false;
  }
};
const setPeriod = p => {
  period.value = p;
  fetchSummary();
};
// 导出当前区间考勤 CSV（带鉴权，走 axios blob 触发下载）。
const exporting = ref(false);
const exportCsv = async () => {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const { data } = await axios.get(`${api()}/export`, {
      params: {
        period: period.value,
        date: summaryDate.value,
        group_id: summaryGroupId.value || undefined,
      },
      responseType: 'blob',
    });
    const url = URL.createObjectURL(new Blob([data], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `考勤_${summaryDate.value}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert('导出失败，请重试');
  } finally {
    exporting.value = false;
  }
};
const shiftSummaryDate = delta => {
  const d = new Date(`${summaryDate.value}T12:00:00`);
  if (period.value === 'day') d.setDate(d.getDate() + delta);
  else if (period.value === 'week') d.setDate(d.getDate() + delta * 7);
  else d.setMonth(d.getMonth() + delta);
  summaryDate.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(
    d.getDate()
  )}`;
  fetchSummary();
};
const rangeLabel = computed(() => {
  if (period.value === 'month') return summaryDate.value.slice(0, 7);
  if (period.value === 'day') return summaryDate.value;
  if (summaryRange.value) {
    return `${summaryRange.value.start} ~ ${summaryRange.value.end}`;
  }
  return summaryDate.value;
});
// 打卡率仪表盘：已到岗 / 应到，环形进度用（周长 2πr, r=52）。
const GAUGE_R = 52;
const GAUGE_CIRC = 2 * Math.PI * GAUGE_R;
const gaugePct = computed(() => {
  const o = overview.value;
  if (!o || !o.expected) return 0;
  return Math.min(1, o.present / o.expected);
});
const gaugeDash = computed(
  () => `${(gaugePct.value * GAUGE_CIRC).toFixed(1)} ${GAUGE_CIRC}`
);

// ── HR 修正 ──
const adjustDialog = ref(null);
const adjustForm = reactive({
  userId: null,
  name: '',
  workDate: '',
  status: 'NORMAL',
  note: '',
});
const { isDirty, markPristine } = useDirtyGuard(() => adjustForm);
const adjusting = ref(false);
const openAdjust = row => {
  adjustForm.userId = row.user_id;
  adjustForm.name = row.name;
  adjustForm.workDate = todayStr();
  adjustForm.status = 'NORMAL';
  adjustForm.note = '';
  markPristine();
  adjustDialog.value?.open();
};
const saveAdjust = async () => {
  if (adjusting.value || !adjustForm.workDate) return;
  adjusting.value = true;
  try {
    await axios.post(`${api()}/adjust`, {
      user_id: adjustForm.userId,
      work_date: adjustForm.workDate,
      status: adjustForm.status,
      note: adjustForm.note || null,
    });
    adjustDialog.value?.close();
    useAlert('已修正');
    fetchSummary();
  } catch (e) {
    useAlert(e.response?.data?.error || '修正失败');
  } finally {
    adjusting.value = false;
  }
};

// ── 考勤组管理（超管/管理员）：多组规则，不同部门不同上下班时间 ──
const groupsUrl = () =>
  `/api/v1/accounts/${accountId.value}/crm/attendance_groups`;
const groups = ref([]);
const selectedGroupId = ref(null);
const pendingDeleteGroup = ref(false);
const savingSetting = ref(false);
const groupForm = reactive({
  name: '',
  isDefault: false,
  workDays: [1, 2, 3, 4, 5],
  clockIn: '09:00',
  clockOut: '18:00',
  breakStart: '12:00',
  breakEnd: '13:30',
  grace: 0,
  reclockLimit: 3,
  reclockWindowDays: 30,
  holidays: [],
  extraWorkdays: [],
  userIds: [],
  // 打卡范围
  geoEnabled: false,
  officeLat: null,
  officeLng: null,
  geoRadius: 300,
  ipEnabled: false,
  allowedIps: [],
});
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

// 组织架构：部门树 + 归属，用来把「组成员」按部门分组选择（比平铺清爽）。
const departments = ref([]);
const memberships = ref([]);
const collapsedDepts = reactive({});
const fetchOrg = async () => {
  try {
    const [dept, mem] = await Promise.all([
      axios.get(`/api/v1/accounts/${accountId.value}/org/departments`),
      axios.get(`/api/v1/accounts/${accountId.value}/org/memberships`),
    ]);
    departments.value = dept.data?.payload || [];
    memberships.value = mem.data?.payload || [];
  } catch {
    departments.value = [];
    memberships.value = [];
  }
};

// 部门按组织架构树 DFS 展平（保留层级 depth 做缩进），同级按 position 排。
const orderedDepts = computed(() => {
  const byParent = {};
  departments.value.forEach(d => {
    (byParent[d.parent_id || 0] ||= []).push(d);
  });
  Object.values(byParent).forEach(arr =>
    arr.sort((a, b) => a.position - b.position || a.id - b.id)
  );
  const out = [];
  const walk = (pid, depth) => {
    (byParent[pid] || []).forEach(d => {
      out.push({ id: d.id, name: d.name, depth });
      walk(d.id, depth + 1);
    });
  };
  walk(0, 0);
  return out;
});

// 用户 → 归属部门 id：优先 is_primary，其次首个归属；无归属归 0（未分配）。
const userDeptMap = computed(() => {
  const map = {};
  memberships.value.forEach(m => {
    if (m.is_primary) map[m.user_id] = m.department_id;
  });
  memberships.value.forEach(m => {
    if (map[m.user_id] == null) map[m.user_id] = m.department_id;
  });
  return map;
});

// 组成员按部门分组：{ id, name, depth, members[] }，未分配部门排最后。
const memberGroups = computed(() => {
  const byDept = {};
  agents.value.forEach(a => {
    (byDept[userDeptMap.value[a.id] ?? 0] ||= []).push(a);
  });
  const list = orderedDepts.value
    .filter(d => byDept[d.id]?.length)
    .map(d => ({ ...d, members: byDept[d.id] }));
  if (byDept[0]?.length) {
    list.push({ id: 0, name: '未分配部门', depth: 0, members: byDept[0] });
  }
  return list;
});

const deptSelectedCount = g =>
  g.members.filter(m => groupForm.userIds.includes(m.id)).length;
const deptAllChecked = g =>
  g.members.length > 0 &&
  g.members.every(m => groupForm.userIds.includes(m.id));
const toggleDept = g => {
  const ids = g.members.map(m => m.id);
  if (deptAllChecked(g)) {
    groupForm.userIds = groupForm.userIds.filter(id => !ids.includes(id));
  } else {
    ids.forEach(id => {
      if (!groupForm.userIds.includes(id)) groupForm.userIds.push(id);
    });
  }
};
const toggleCollapse = id => {
  collapsedDepts[id] = !collapsedDepts[id];
};
const loadGroupForm = g => {
  groupForm.name = g?.name || '';
  groupForm.isDefault = !!g?.is_default;
  groupForm.workDays = [...(g?.work_days || [1, 2, 3, 4, 5])];
  groupForm.clockIn = g?.clock_in_time || '09:00';
  groupForm.clockOut = g?.clock_out_time || '18:00';
  groupForm.breakStart = g?.break_start_time ?? '12:00';
  groupForm.breakEnd = g?.break_end_time ?? '13:30';
  groupForm.grace = g?.grace_minutes ?? 0;
  groupForm.reclockLimit = g?.reclock_limit ?? 3;
  groupForm.reclockWindowDays = g?.reclock_window_days ?? 30;
  groupForm.holidays = [...(g?.holidays || [])];
  groupForm.extraWorkdays = [...(g?.extra_workdays || [])];
  groupForm.userIds = [...(g?.user_ids || [])];
  groupForm.geoEnabled = !!g?.geo_enabled;
  groupForm.officeLat = g?.office_lat ?? null;
  groupForm.officeLng = g?.office_lng ?? null;
  groupForm.geoRadius = g?.geo_radius_m ?? 300;
  groupForm.ipEnabled = !!g?.ip_enabled;
  groupForm.allowedIps = [...(g?.allowed_ips || [])];
};
const selectGroup = g => {
  selectedGroupId.value = g.id;
  pendingDeleteGroup.value = false;
  loadGroupForm(g);
};
const newGroup = () => {
  selectedGroupId.value = null;
  pendingDeleteGroup.value = false;
  loadGroupForm(null);
};
const fetchGroups = async () => {
  try {
    const { data } = await axios.get(groupsUrl());
    groups.value = data.payload || [];
    const keep = groups.value.find(g => g.id === selectedGroupId.value);
    selectGroup(keep || groups.value[0]);
  } catch {
    groups.value = [];
  }
};
const openSettings = () => {
  view.value = 'settings';
  fetchGroups();
  if (!agents.value.length) fetchAgents();
  if (!departments.value.length) fetchOrg();
};
const newHoliday = ref('');
const addHoliday = () => {
  const d = newHoliday.value;
  if (!d || groupForm.holidays.includes(d)) return;
  groupForm.holidays.push(d);
  groupForm.holidays.sort();
  newHoliday.value = '';
};
const removeHoliday = d => {
  groupForm.holidays = groupForm.holidays.filter(x => x !== d);
};
const newExtraWorkday = ref('');
const addExtraWorkday = () => {
  const d = newExtraWorkday.value;
  if (!d || groupForm.extraWorkdays.includes(d)) return;
  groupForm.extraWorkdays.push(d);
  groupForm.extraWorkdays.sort();
  newExtraWorkday.value = '';
};
const removeExtraWorkday = d => {
  groupForm.extraWorkdays = groupForm.extraWorkdays.filter(x => x !== d);
};
const toggleWorkDay = d => {
  const i = groupForm.workDays.indexOf(d);
  if (i >= 0) groupForm.workDays.splice(i, 1);
  else groupForm.workDays.push(d);
};
const toggleMember = id => {
  const i = groupForm.userIds.indexOf(id);
  if (i >= 0) groupForm.userIds.splice(i, 1);
  else groupForm.userIds.push(id);
};
// 抓取当前位置设为办公室坐标（管理员在办公室点一下）。
const capturingGeo = ref(false);
const captureOfficeLocation = () => {
  if (!navigator.geolocation) {
    useAlert('当前浏览器不支持定位');
    return;
  }
  capturingGeo.value = true;
  navigator.geolocation.getCurrentPosition(
    pos => {
      groupForm.officeLat = Number(pos.coords.latitude.toFixed(7));
      groupForm.officeLng = Number(pos.coords.longitude.toFixed(7));
      capturingGeo.value = false;
      useAlert('已抓取当前位置为办公室坐标');
    },
    () => {
      capturingGeo.value = false;
      useAlert('定位失败：请允许定位权限后重试');
    },
    { enableHighAccuracy: true, timeout: 8000 }
  );
};

// 把当前网络的公网 IP 设为打卡网络（管理员在办公室 WiFi 下点一下）。
const capturingIp = ref(false);
const captureCurrentIp = async () => {
  capturingIp.value = true;
  try {
    const { data } = await axios.get(`${api()}/my_network`);
    const ip = data?.ip;
    if (ip && !groupForm.allowedIps.includes(ip)) {
      groupForm.allowedIps.push(ip);
      useAlert(`已把当前网络 ${ip} 设为打卡网络`);
    } else if (ip) {
      useAlert('当前网络已在打卡网络列表中');
    }
  } catch {
    useAlert('获取当前网络失败');
  } finally {
    capturingIp.value = false;
  }
};
const removeIp = ip => {
  groupForm.allowedIps = groupForm.allowedIps.filter(x => x !== ip);
};

const saveGroup = async () => {
  if (savingSetting.value || !groupForm.name.trim()) return;
  savingSetting.value = true;
  const payload = {
    group: {
      name: groupForm.name.trim(),
      work_days: groupForm.workDays,
      clock_in_time: groupForm.clockIn,
      clock_out_time: groupForm.clockOut,
      break_start_time: groupForm.breakStart,
      break_end_time: groupForm.breakEnd,
      grace_minutes: groupForm.grace,
      reclock_limit: groupForm.reclockLimit,
      reclock_window_days: groupForm.reclockWindowDays,
      holidays: groupForm.holidays,
      extra_workdays: groupForm.extraWorkdays,
      user_ids: groupForm.userIds,
      geo_enabled: groupForm.geoEnabled,
      office_lat: groupForm.officeLat,
      office_lng: groupForm.officeLng,
      geo_radius_m: groupForm.geoRadius,
      ip_enabled: groupForm.ipEnabled,
      allowed_ips: groupForm.allowedIps,
    },
  };
  try {
    if (selectedGroupId.value) {
      await axios.put(`${groupsUrl()}/${selectedGroupId.value}`, payload);
    } else {
      const { data } = await axios.post(groupsUrl(), payload);
      selectedGroupId.value = data.id;
    }
    useAlert('考勤组已保存');
    fetchGroups();
    fetchMine();
  } catch (e) {
    useAlert(e.response?.data?.error || '保存失败');
  } finally {
    savingSetting.value = false;
  }
};
const deleteGroup = async () => {
  if (!selectedGroupId.value || groupForm.isDefault) return;
  if (!pendingDeleteGroup.value) {
    pendingDeleteGroup.value = true;
    return;
  }
  pendingDeleteGroup.value = false;
  try {
    await axios.delete(`${groupsUrl()}/${selectedGroupId.value}`);
    selectedGroupId.value = null;
    useAlert('考勤组已删除，组内成员回归默认组');
    fetchGroups();
  } catch (e) {
    useAlert(e.response?.data?.error || '删除失败');
  }
};

const loadView = () => {
  if (view.value === 'summary') fetchSummary();
  else fetchMine();
};
const shiftMonth = delta => {
  const [y, m] = month.value.split('-').map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  month.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
  loadView();
};
const switchView = v => {
  view.value = v;
  if (v === 'settings') openSettings();
  else loadView();
};

onMounted(fetchMine);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex flex-wrap items-center justify-between gap-2 flex-shrink-0 px-4 py-3 sm:px-6 sm:py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">考勤</h1>
      <div class="flex flex-wrap items-center gap-2" data-tabbar="page">
        <button
          :aria-selected="view === 'mine'"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'mine'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('mine')"
        >
          我的考勤
        </button>
        <button
          v-if="canSummary"
          :aria-selected="view === 'summary'"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'summary'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('summary')"
        >
          考勤汇总
        </button>
        <button
          v-if="isAdminLike"
          :aria-selected="view === 'settings'"
          class="h-8 px-3 text-sm rounded-lg border"
          :class="
            view === 'settings'
              ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="switchView('settings')"
        >
          规则设置
        </button>
      </div>
    </div>

    <div class="flex flex-col gap-4 px-4 py-4 sm:px-6 sm:py-5">
      <!-- 打卡卡片（始终显示） -->
      <div
        v-if="view !== 'settings'"
        class="flex flex-wrap items-center gap-4 p-4 border rounded-2xl border-n-weak bg-n-solid-1/60"
      >
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            今天 {{ todayStr() }}
          </span>
          <span v-if="setting" class="text-xs text-n-slate-11">
            {{ setting.name ? `${setting.name} · ` : '' }}工作时间
            {{ setting.clock_in_time }} – {{ setting.clock_out_time }}
            <template v-if="setting.grace_minutes">
              （宽限 {{ setting.grace_minutes }} 分钟）
            </template>
          </span>
          <span v-else class="text-xs text-n-slate-10">
            你还没加入任何考勤组，暂无打卡规则，请联系管理员分配
          </span>
          <span
            v-if="lateHint"
            class="inline-flex items-center gap-1 mt-0.5 text-xs font-medium text-n-amber-11"
          >
            <span class="i-lucide-alarm-clock size-3.5" />
            {{ lateHint }}
          </span>
        </div>
        <div class="flex items-center gap-4 ml-auto">
          <div class="flex flex-col items-center gap-0.5 text-xs">
            <span class="text-n-slate-10">上班</span>
            <span class="font-medium text-n-slate-12">
              {{ todayRec?.clock_in_at || '—' }}
            </span>
          </div>
          <div class="flex flex-col items-center gap-0.5 text-xs">
            <span class="text-n-slate-10">下班</span>
            <span class="font-medium text-n-slate-12">
              {{ todayRec?.clock_out_at || '—' }}
            </span>
          </div>
          <span
            v-if="todayRec"
            class="px-2 py-0.5 text-xs rounded-full"
            :class="STATUS_META[todayRec.status]?.cls"
          >
            {{ STATUS_META[todayRec.status]?.label }}
          </span>
          <button
            class="h-10 px-6 text-sm font-medium text-white rounded-xl shrink-0 whitespace-nowrap bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="clocking"
            @click="clock()"
          >
            {{ willClockOut ? '下班打卡' : '上班打卡' }}
          </button>
          <button
            class="h-10 px-4 text-sm font-medium rounded-xl shrink-0 whitespace-nowrap border border-n-blue-7 text-n-blue-11 hover:bg-n-blue-3 disabled:opacity-50"
            :disabled="clocking"
            title="出差 / 客户现场打卡，不受打卡范围限制"
            @click="clock(true)"
          >
            外勤打卡
          </button>
        </div>
      </div>

      <!-- 月份切换（我的考勤）：紫玻璃月份选择器，可直接跳月 -->
      <div v-if="view === 'mine'" class="flex items-center gap-2">
        <button
          class="flex items-center justify-center rounded-lg size-8 border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          title="上个月"
          @click="shiftMonth(-1)"
        >
          <span class="i-lucide-chevron-left size-4" />
        </button>
        <MonthPicker
          v-model="month"
          :clearable="false"
          trigger-class="w-32 h-8"
          @change="loadView"
        />
        <button
          class="flex items-center justify-center rounded-lg size-8 border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
          title="下个月"
          @click="shiftMonth(1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </div>

      <!-- ── 我的考勤：月历 ── -->
      <template v-if="view === 'mine'">
        <div
          v-if="loadingMine"
          class="py-10 text-sm text-center text-n-slate-11 max-w-2xl"
        >
          加载中…
        </div>
        <div v-else class="grid grid-cols-7 gap-1.5 max-w-2xl">
          <div
            v-for="w in WEEK_LABELS"
            :key="w"
            class="py-1 text-xs text-center text-n-slate-10"
          >
            {{ w }}
          </div>
          <template v-for="(d, i) in calendarCells" :key="i">
            <div v-if="!d" />
            <div
              v-else
              class="flex flex-col items-center gap-0.5 py-1.5 border rounded-lg border-n-weak/60"
              :class="
                `${month}-${pad(d)}` === todayStr()
                  ? 'ring-1 ring-n-iris-9'
                  : ''
              "
            >
              <span class="text-xs text-n-slate-12">{{ d }}</span>
              <span
                v-if="dayStatus(d)"
                class="px-1.5 py-0.5 text-[10px] rounded-full"
                :class="STATUS_META[dayStatus(d)]?.cls"
              >
                {{ STATUS_META[dayStatus(d)]?.label }}
              </span>
              <span v-else class="text-[10px] text-n-slate-8">·</span>
            </div>
          </template>
        </div>
        <div class="flex flex-wrap gap-4 text-xs text-n-slate-11">
          <span>出勤 {{ mineCounts.present }} 天</span>
          <span>迟到 {{ mineCounts.late }} 次</span>
          <span>早退 {{ mineCounts.early }} 次</span>
          <span>旷工 {{ mineCounts.absent }} 天</span>
          <span>外勤 {{ mineCounts.field }} 天</span>
          <span>请假 {{ mineCounts.leave }} 天</span>
        </div>
        <!-- 状态颜色图例 -->
        <div class="flex flex-wrap gap-x-3 gap-y-1.5 max-w-2xl">
          <span
            v-for="(meta, key) in STATUS_META"
            :key="key"
            class="px-1.5 py-0.5 text-[10px] rounded-full"
            :class="meta.cls"
          >
            {{ meta.label }}
          </span>
        </div>
        <!-- 旷工/迟到快捷入口：跳转 OA 提交补卡/请假 -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-xs text-n-slate-10">卡有问题？</span>
          <button
            class="h-7 px-3 text-xs rounded-lg border border-n-iris-7 text-n-iris-11 hover:bg-n-iris-3"
            @click="goApproval('reclock')"
          >
            申请补卡
          </button>
          <button
            class="h-7 px-3 text-xs rounded-lg border border-n-iris-7 text-n-iris-11 hover:bg-n-iris-3"
            @click="goApproval('leave')"
          >
            请假申请
          </button>
        </div>
      </template>

      <!-- ── 考勤汇总 ── -->
      <template v-else-if="view === 'summary'">
        <!-- 粒度切换 + 区间导航 -->
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex p-0.5 rounded-lg bg-n-alpha-1">
            <button
              v-for="p in PERIODS"
              :key="p.value"
              class="h-8 px-4 text-sm rounded-md"
              :class="
                period === p.value
                  ? 'bg-n-solid-1 text-n-iris-11 font-medium shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="setPeriod(p.value)"
            >
              {{ p.label }}统计
            </button>
          </div>
          <div class="flex items-center gap-1">
            <button
              class="h-8 px-2 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
              @click="shiftSummaryDate(-1)"
            >
              ‹
            </button>
            <span
              class="min-w-[7rem] text-sm font-medium text-center text-n-slate-12"
            >
              {{ rangeLabel }}
            </span>
            <button
              class="h-8 px-2 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
              @click="shiftSummaryDate(1)"
            >
              ›
            </button>
          </div>
          <SelectCard
            v-if="summaryGroupOptions.length > 1"
            v-model="summaryGroupId"
            :options="summaryGroupOptions"
            trigger-class="w-36 h-8 ml-auto"
            @update:model-value="fetchSummary"
          />
          <button
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
            :class="summaryGroupOptions.length > 1 ? '' : 'ml-auto'"
            :disabled="exporting || !summaryRows.length"
            title="导出当前区间考勤为 CSV（Excel 可打开）"
            @click="exportCsv"
          >
            <span class="i-lucide-download size-4" />
            导出
          </button>
        </div>

        <!-- 今日/区间概览仪表盘 -->
        <div
          v-if="overview"
          class="flex flex-wrap items-center gap-6 p-4 border rounded-2xl border-n-weak bg-n-solid-1/60"
        >
          <div class="relative shrink-0 size-28">
            <svg viewBox="0 0 120 120" class="-rotate-90 size-28">
              <circle
                cx="60"
                cy="60"
                r="52"
                fill="none"
                stroke-width="12"
                class="stroke-n-alpha-2"
              />
              <circle
                cx="60"
                cy="60"
                r="52"
                fill="none"
                stroke-width="12"
                stroke-linecap="round"
                class="stroke-n-iris-9"
                :stroke-dasharray="gaugeDash"
              />
            </svg>
            <div
              class="absolute inset-0 flex flex-col items-center justify-center"
            >
              <span class="text-xl font-semibold text-n-slate-12">
                {{ overview.present }}/{{ overview.expected }}
              </span>
              <span class="text-[11px] text-n-slate-10">已打卡/应到</span>
            </div>
          </div>
          <div
            class="grid flex-1 grid-cols-3 gap-3 sm:grid-cols-6 min-w-[240px]"
          >
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-slate-12">
                {{ overview.expected }}
              </span>
              <span class="text-xs text-n-slate-10">应到</span>
            </div>
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-teal-11">
                {{ overview.present }}
              </span>
              <span class="text-xs text-n-slate-10">已打卡</span>
            </div>
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-amber-11">
                {{ overview.late }}
              </span>
              <span class="text-xs text-n-slate-10">迟到</span>
            </div>
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-ruby-11">
                {{ overview.absent }}
              </span>
              <span class="text-xs text-n-slate-10">旷工</span>
            </div>
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-blue-11">
                {{ overview.field }}
              </span>
              <span class="text-xs text-n-slate-10">外勤</span>
            </div>
            <div
              class="flex flex-col items-center gap-1 p-3 rounded-xl bg-n-alpha-1"
            >
              <span class="text-xl font-semibold text-n-iris-11">
                {{ overview.leave }}
              </span>
              <span class="text-xs text-n-slate-10">请假</span>
            </div>
          </div>
        </div>

        <!-- 今日未打卡名单（负责人早上一眼看谁没到） -->
        <div
          v-if="notClockedToday.length"
          class="flex flex-wrap items-center gap-2 p-3 border rounded-2xl border-n-amber-6 bg-n-amber-3/40"
        >
          <span class="text-sm font-medium text-n-amber-11">
            <span class="i-lucide-user-x size-4 align-middle" />
            今日未打卡（{{ notClockedToday.length }}）
          </span>
          <span
            v-for="p in notClockedToday"
            :key="p.user_id"
            class="px-2 py-0.5 text-xs rounded-full bg-n-solid-1/70 text-n-slate-11"
          >
            {{ p.name }}
          </span>
        </div>

        <!-- 手机卡片 -->
        <div class="flex flex-col gap-2 md:hidden">
          <p
            v-if="loadingSummary"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            加载中…
          </p>
          <div
            v-for="row in summaryRows"
            v-else
            :key="row.user_id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium truncate text-n-slate-12">
                {{ row.name }}
              </span>
              <span class="flex-1" />
              <button
                v-if="isAdminLike"
                class="text-xs shrink-0 text-n-iris-11 hover:underline"
                @click.stop="openAdjust(row)"
              >
                修正
              </button>
            </div>
            <div
              class="flex flex-wrap gap-x-3 gap-y-1 mt-2 text-xs text-n-slate-11"
            >
              <span>出勤：{{ row.present }}</span>
              <span :class="row.late ? 'text-n-amber-11' : ''">
                迟到：{{ row.late }}
              </span>
              <span :class="row.early_leave ? 'text-n-amber-11' : ''">
                早退：{{ row.early_leave }}
              </span>
              <span :class="row.absent ? 'text-n-ruby-11' : ''">
                旷工：{{ row.absent }}
              </span>
              <span :class="row.field ? 'text-n-blue-11' : ''">
                外勤：{{ row.field }}
              </span>
              <span>请假：{{ row.leave }}</span>
            </div>
          </div>
        </div>
        <div
          class="hidden overflow-x-auto border rounded-xl md:block border-n-weak"
        >
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left border-b text-n-slate-11 border-n-weak">
                <th class="px-3 py-2 font-medium">成员</th>
                <th class="px-3 py-2 font-medium">出勤</th>
                <th class="px-3 py-2 font-medium">迟到</th>
                <th class="px-3 py-2 font-medium">早退</th>
                <th class="px-3 py-2 font-medium">旷工</th>
                <th class="px-3 py-2 font-medium">外勤</th>
                <th class="px-3 py-2 font-medium">请假</th>
                <th v-if="isAdminLike" class="px-3 py-2 font-medium text-right">
                  操作
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="loadingSummary">
                <td colspan="8" class="px-3 py-6 text-center text-n-slate-11">
                  加载中…
                </td>
              </tr>
              <template v-else>
                <tr
                  v-for="row in summaryRows"
                  :key="row.user_id"
                  class="border-b border-n-weak/60 text-n-slate-12"
                >
                  <td class="px-3 py-2">{{ row.name }}</td>
                  <td class="px-3 py-2">{{ row.present }}</td>
                  <td
                    class="px-3 py-2"
                    :class="row.late ? 'text-n-amber-11' : ''"
                  >
                    {{ row.late }}
                  </td>
                  <td
                    class="px-3 py-2"
                    :class="row.early_leave ? 'text-n-amber-11' : ''"
                  >
                    {{ row.early_leave }}
                  </td>
                  <td
                    class="px-3 py-2"
                    :class="row.absent ? 'text-n-ruby-11' : ''"
                  >
                    {{ row.absent }}
                  </td>
                  <td
                    class="px-3 py-2"
                    :class="row.field ? 'text-n-blue-11' : ''"
                  >
                    {{ row.field }}
                  </td>
                  <td class="px-3 py-2">{{ row.leave }}</td>
                  <td v-if="isAdminLike" class="px-3 py-2 text-right">
                    <button
                      class="text-xs text-n-iris-11 hover:underline"
                      @click="openAdjust(row)"
                    >
                      修正
                    </button>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <p class="text-xs text-n-slate-10">
          口径：只统计工作日且不含未来日期；旷工=当天没有任何打卡记录；外勤=出差/客户现场打卡（计出勤、单列，不判迟到）；修正会留审计痕迹。
        </p>
      </template>

      <!-- ── 考勤组管理：多组规则，不同部门不同上下班时间 ── -->
      <template v-else>
        <div class="flex flex-col gap-4 lg:flex-row">
          <!-- 组列表 -->
          <div class="flex flex-col gap-1.5 w-full lg:w-56 shrink-0">
            <button
              v-for="g in groups"
              :key="g.id"
              class="flex items-center justify-between px-3 py-2 text-sm text-left border rounded-lg"
              :class="
                g.id === selectedGroupId
                  ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
                  : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-2'
              "
              @click="selectGroup(g)"
            >
              <span class="truncate">{{ g.name }}</span>
              <span class="text-xs shrink-0 text-n-slate-10">
                {{ g.is_default ? '默认' : `${g.user_ids.length} 人` }}
              </span>
            </button>
            <button
              class="px-3 py-2 text-sm border border-dashed rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
              @click="newGroup"
            >
              ＋ 新建考勤组
            </button>
            <p class="text-xs text-n-slate-10">
              未分组成员按「默认考勤组」执行；一人只能属于一个组。
            </p>
          </div>

          <!-- 组规则表单 -->
          <div class="flex flex-col max-w-md gap-4">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">组名</span>
              <input
                v-model="groupForm.name"
                :disabled="groupForm.isDefault"
                class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 disabled:opacity-60"
                placeholder="如 行政组 / 业务组"
              />
            </label>
            <div class="flex flex-col gap-1.5">
              <span class="text-xs text-n-slate-11">工作日</span>
              <div class="flex gap-2">
                <button
                  v-for="(w, i) in WEEK_LABELS"
                  :key="w"
                  class="w-9 h-9 text-sm rounded-lg border"
                  :class="
                    groupForm.workDays.includes(i + 1)
                      ? 'border-n-iris-9 bg-n-iris-9/10 text-n-iris-11 font-medium'
                      : 'border-n-weak text-n-slate-11'
                  "
                  @click="toggleWorkDay(i + 1)"
                >
                  {{ w }}
                </button>
              </div>
            </div>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">上班时间</span>
                <input
                  v-model="groupForm.clockIn"
                  type="time"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">下班时间</span>
                <input
                  v-model="groupForm.clockOut"
                  type="time"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">午休开始</span>
                <input
                  v-model="groupForm.breakStart"
                  type="time"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">午休结束</span>
                <input
                  v-model="groupForm.breakEnd"
                  type="time"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              午休会从工作时长里扣除，并把一天切成上午/下午两段——请假单按这个切分自动判半天假。两头都留空表示不设午休。
            </p>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">宽限（分钟）</span>
                <input
                  v-model.number="groupForm.grace"
                  type="number"
                  min="0"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">每月补卡上限</span>
                <input
                  v-model.number="groupForm.reclockLimit"
                  type="number"
                  min="0"
                  title="0 = 不允许补卡"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">补卡时限（天）</span>
                <input
                  v-model.number="groupForm.reclockWindowDays"
                  type="number"
                  min="0"
                  title="只能补 N 天内的卡；0 = 不限"
                  class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                />
              </label>
            </div>
            <p class="text-xs text-n-slate-10">
              补卡上限 0 = 不允许补卡；补卡时限 0 =
              不限。提交补卡审批时按申请人所属组校验。
            </p>

            <!-- 打卡范围（钉钉式：定位 + 办公网络，任一命中即可打卡）-->
            <div
              class="flex flex-col gap-3 p-3 border rounded-xl border-n-weak bg-n-alpha-1"
            >
              <span class="text-sm font-medium text-n-slate-12"
                >打卡范围（可选）</span
              >

              <!-- GPS 定位打卡 -->
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="groupForm.geoEnabled"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
                <span class="text-sm text-n-slate-12"
                  >定位打卡（GPS 地理围栏）</span
                >
              </label>
              <div v-if="groupForm.geoEnabled" class="flex flex-col gap-2 pl-6">
                <div class="flex flex-wrap items-center gap-2">
                  <button
                    class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-60"
                    :disabled="capturingGeo"
                    @click="captureOfficeLocation"
                  >
                    {{ capturingGeo ? '定位中…' : '抓取当前位置为办公室' }}
                  </button>
                  <span class="text-xs text-n-slate-11">
                    {{
                      groupForm.officeLat
                        ? `已设：${groupForm.officeLat}, ${groupForm.officeLng}`
                        : '尚未设置办公室坐标'
                    }}
                  </span>
                </div>
                <label class="flex items-center gap-2">
                  <span class="text-xs text-n-slate-11">允许半径（米）</span>
                  <input
                    v-model.number="groupForm.geoRadius"
                    type="number"
                    min="20"
                    class="w-24 h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
                  />
                </label>
              </div>

              <!-- 办公网络(IP)打卡 -->
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  v-model="groupForm.ipEnabled"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
                <span class="text-sm text-n-slate-12">
                  办公网络打卡（连公司 WiFi/网络才能打）
                </span>
              </label>
              <div v-if="groupForm.ipEnabled" class="flex flex-col gap-2 pl-6">
                <button
                  class="self-start h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-60"
                  :disabled="capturingIp"
                  @click="captureCurrentIp"
                >
                  {{ capturingIp ? '获取中…' : '把当前网络设为打卡网络' }}
                </button>
                <div
                  v-if="groupForm.allowedIps.length"
                  class="flex flex-wrap gap-1.5"
                >
                  <span
                    v-for="ip in groupForm.allowedIps"
                    :key="ip"
                    class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
                  >
                    {{ ip }}
                    <button
                      class="text-n-slate-10 hover:text-n-ruby-11"
                      @click="removeIp(ip)"
                    >
                      <span class="i-lucide-x size-3" />
                    </button>
                  </span>
                </div>
                <p class="text-xs text-n-slate-10">
                  在公司 WiFi 下点上面按钮抓取公司公网 IP。手机浏览器读不到 WiFi
                  名，故用「连同一网络=同一公网 IP」来判定，等效 WiFi 打卡。
                </p>
              </div>
              <p class="text-xs text-n-slate-10">
                两项都不开 =
                不限制打卡地点；都开则「在定位范围内」或「在办公网络」任一满足即可打卡。
              </p>
            </div>

            <div class="flex flex-col gap-1.5">
              <span class="text-xs text-n-slate-11">
                节假日（不计工作日，如法定假期）
              </span>
              <div class="flex items-center gap-2">
                <DatePicker v-model="newHoliday" />
                <button
                  class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
                  @click="addHoliday"
                >
                  添加
                </button>
              </div>
              <div
                v-if="groupForm.holidays.length"
                class="flex flex-wrap gap-1.5"
              >
                <span
                  v-for="d in groupForm.holidays"
                  :key="d"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-11"
                >
                  {{ d }}
                  <button
                    class="hover:text-n-ruby-11"
                    @click="removeHoliday(d)"
                  >
                    ×
                  </button>
                </span>
              </div>
            </div>

            <div class="flex flex-col gap-1.5">
              <span class="text-xs text-n-slate-11">
                额外上班日（调休补班，如某个周六上班）
              </span>
              <div class="flex items-center gap-2">
                <DatePicker v-model="newExtraWorkday" />
                <button
                  class="h-9 px-3 text-sm rounded-lg border border-n-weak text-n-slate-12 hover:bg-n-alpha-2"
                  @click="addExtraWorkday"
                >
                  添加
                </button>
              </div>
              <div
                v-if="groupForm.extraWorkdays.length"
                class="flex flex-wrap gap-1.5"
              >
                <span
                  v-for="d in groupForm.extraWorkdays"
                  :key="d"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  {{ d }}
                  <button
                    class="hover:text-n-ruby-11"
                    @click="removeExtraWorkday(d)"
                  >
                    ×
                  </button>
                </span>
              </div>
            </div>
            <div v-if="!groupForm.isDefault" class="flex flex-col gap-1.5">
              <div class="flex items-center justify-between">
                <span class="text-xs text-n-slate-11"
                  >组成员（按部门选择）</span
                >
                <span class="text-xs text-n-slate-10">
                  已选 {{ groupForm.userIds.length }} 人
                </span>
              </div>
              <div
                class="flex flex-col overflow-hidden border divide-y rounded-lg border-n-weak divide-n-weak"
              >
                <div
                  v-for="g in memberGroups"
                  :key="g.id"
                  class="flex flex-col"
                >
                  <!-- 部门头：折叠 + 全选本部门 -->
                  <div
                    class="flex items-center gap-2 px-3 py-2 bg-n-alpha-1"
                    :style="{ paddingLeft: `${12 + g.depth * 16}px` }"
                  >
                    <button
                      type="button"
                      class="flex items-center gap-1 text-sm font-medium text-n-slate-12"
                      @click="toggleCollapse(g.id)"
                    >
                      <span
                        class="size-4 text-n-slate-10"
                        :class="
                          collapsedDepts[g.id]
                            ? 'i-lucide-chevron-right'
                            : 'i-lucide-chevron-down'
                        "
                      />
                      {{ g.name }}
                    </button>
                    <span class="text-xs text-n-slate-10">
                      {{ deptSelectedCount(g) }}/{{ g.members.length }}
                    </span>
                    <label
                      class="flex items-center gap-1 ml-auto text-xs cursor-pointer text-n-slate-11"
                    >
                      <input
                        type="checkbox"
                        class="accent-n-iris-9"
                        :checked="deptAllChecked(g)"
                        @change="toggleDept(g)"
                      />
                      全选
                    </label>
                  </div>
                  <!-- 部门成员 -->
                  <div
                    v-if="!collapsedDepts[g.id]"
                    class="flex flex-wrap px-3 py-2 gap-x-4 gap-y-1.5"
                  >
                    <label
                      v-for="a in g.members"
                      :key="a.id"
                      class="flex items-center gap-1.5 text-sm cursor-pointer text-n-slate-11"
                    >
                      <input
                        type="checkbox"
                        class="accent-n-iris-9"
                        :checked="groupForm.userIds.includes(a.id)"
                        @change="toggleMember(a.id)"
                      />
                      {{ a.name }}
                    </label>
                  </div>
                </div>
                <div
                  v-if="!memberGroups.length"
                  class="px-3 py-4 text-sm text-center text-n-slate-10"
                >
                  暂无成员，请先在「组织架构」维护部门与人员
                </div>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <button
                class="h-9 px-5 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
                :disabled="
                  savingSetting ||
                  !groupForm.name.trim() ||
                  !groupForm.workDays.length
                "
                @click="saveGroup"
              >
                {{ savingSetting ? '保存中…' : '保存考勤组' }}
              </button>
              <button
                v-if="selectedGroupId && !groupForm.isDefault"
                class="h-9 px-4 text-sm rounded-lg"
                :class="
                  pendingDeleteGroup
                    ? 'bg-n-ruby-9 text-white hover:bg-n-ruby-10'
                    : 'text-n-ruby-11 hover:bg-n-ruby-3'
                "
                @click="deleteGroup"
              >
                {{ pendingDeleteGroup ? '确认删除' : '删除考勤组' }}
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- HR 修正弹窗 -->
    <Dialog
      ref="adjustDialog"
      :title="`修正考勤 · ${adjustForm.name}`"
      :show-confirm-button="false"
      :dirty="isDirty"
      dirty-save-label="保存"
      @close="markPristine"
      @save="saveAdjust"
    >
      <div class="flex flex-col gap-4">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">日期</span>
          <DatePicker v-model="adjustForm.workDate" block />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">状态</span>
          <SelectCard
            v-model="adjustForm.status"
            :options="statusOptions"
            block
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">备注</span>
          <input
            v-model="adjustForm.note"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="如：出差外勤 / 忘打卡补正常"
          />
        </label>
        <div class="flex justify-end">
          <button
            type="button"
            class="h-9 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="adjusting"
            @click="saveAdjust"
          >
            {{ adjusting ? '保存中…' : '保存修正' }}
          </button>
        </div>
      </div>
    </Dialog>
  </div>
</template>
