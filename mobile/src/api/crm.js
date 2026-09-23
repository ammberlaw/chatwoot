// 后端接口的薄封装：把「account 前缀」和参数名收在一处，页面只管业务。
import { http, cachedGet } from './client';
import { useAuthStore } from '@/stores/auth';

const base = () => `/api/v1/accounts/${useAuthStore().accountId}`;

// ── 客户 ──
export const fetchCustomers = params =>
  cachedGet(`${base()}/crm/customers`, { params });

export const fetchCustomerDetail = id =>
  cachedGet(`${base()}/crm/customers/${id}/detail`);

export const createCustomer = customer =>
  http.post(`${base()}/crm/customers`, { customer });

export const updateCustomer = (id, customer) =>
  http.patch(`${base()}/crm/customers/${id}`, { customer });

export const checkCustomerDuplicate = params =>
  http.get(`${base()}/crm/customers/check_duplicate`, { params });

// 列表顶部四个概览数。后端与列表共用同一份 scope，所以筛选参数要原样传进来。
export const fetchCustomerStats = params =>
  cachedGet(`${base()}/crm/customers/stats`, { params });

export const fetchOptionItems = category =>
  cachedGet(`${base()}/crm/option_items`, { params: { category } });

export const createFollowUpNote = note =>
  http.post(`${base()}/crm/follow_up_notes`, { note });

// 认领公海客户；并发下后端用行锁裁决，抢输的一方拿 403
export const claimCustomer = id => http.post(`${base()}/crm/customers/${id}/claim`);

export const releaseCustomer = id => http.post(`${base()}/crm/customers/${id}/release`);

// 分配走专用 reassign（带「只能分给本团队」等权限口径），别直接 PATCH account_owner_id
export const reassignCustomers = (ids, ownerId) =>
  http.post(`${base()}/crm/customers/reassign`, { ids, owner_id: ownerId });

export const attachCustomerFiles = (id, files) => {
  const fd = new FormData();
  files.forEach(f => fd.append('files[]', f));
  return http.post(`${base()}/crm/customers/${id}/attach`, fd);
};

export const detachCustomerFile = (id, attachmentId) =>
  http.delete(`${base()}/crm/customers/${id}/attach/${attachmentId}`);

export const fetchCustomerAudits = id =>
  cachedGet(`${base()}/crm/customers/${id}/audits`);

// scope=all：分配目标可以是任意 CRM 成员
export const fetchAgents = (scope = 'all') =>
  cachedGet(`${base()}/crm/agents`, { params: { scope } });

export const scheduleFollowUp = (id, at, addToSchedule = false) =>
  http.post(`${base()}/crm/customers/${id}/schedule_follow_up`, {
    next_follow_up_at: at,
    add_to_schedule: addToSchedule,
  });

// ── 邮件 ──
export const fetchEmails = params =>
  cachedGet(`${base()}/crm/emails`, { params });

export const fetchEmail = id => cachedGet(`${base()}/crm/emails/${id}`);

export const fetchEmailCounts = params =>
  cachedGet(`${base()}/crm/emails/counts`, { params });

export const updateEmail = (id, email) =>
  http.patch(`${base()}/crm/emails/${id}`, { email });

export const sendEmail = email =>
  http.post(`${base()}/crm/emails`, { email });

// 带附件时必须走 multipart：后端 email[files][] 由 ActiveStorage 直接 attach。
// Capacitor 的 XHR 拦截会把 FormData 里的 File 转 base64 交原生重组，故此路径在
// 真机与浏览器行为一致；但只认真正的 File 对象，Blob 会被当字符串丢掉。
export const sendEmailWithFiles = (email, files) => {
  const fd = new FormData();
  Object.entries(email).forEach(([k, v]) => {
    if (v !== null && v !== undefined) fd.append(`email[${k}]`, v);
  });
  files.forEach(f => fd.append('email[files][]', f));
  return http.post(`${base()}/crm/emails`, fd);
};

export const fetchEmailsFetchNow = () => http.post(`${base()}/crm/emails/fetch`);

export const fetchMailAccounts = () => http.get(`${base()}/crm/mail_accounts`);

export const deleteEmail = id => http.delete(`${base()}/crm/emails/${id}`);

export const fetchEmailTemplates = () =>
  cachedGet(`${base()}/crm/email_templates`);

// ── 邮件 AI 助手（全公司共用一把 key，后端读 DB 配置）──
// 注意后端有 15s Rack::Timeout，模型必须是 deepseek-chat 这类快的
export const aiCompose = (intent, original) =>
  http.post(`${base()}/crm/ai/compose`, { intent, original });

export const aiTranslate = emailId =>
  http.post(`${base()}/crm/ai/translate`, { email_id: emailId });

export const aiSummarize = address =>
  http.post(`${base()}/crm/ai/summarize`, { address });

// ── 审批 ──
export const fetchApprovals = params =>
  cachedGet(`${base()}/oa/approval_requests`, { params });

export const fetchApproval = id =>
  cachedGet(`${base()}/oa/approval_requests/${id}`);

export const fetchApprovalCounts = () =>
  cachedGet(`${base()}/oa/approval_requests/counts`);

export const actOnApproval = (id, action, comment) =>
  http.post(`${base()}/oa/approval_requests/${id}/${action}`, { comment });

export const fetchApprovalTemplates = () =>
  cachedGet(`${base()}/oa/approval_templates`, { params: { active: 'true' } });

export const createApprovalRequest = payload =>
  http.post(`${base()}/oa/approval_requests`, payload);

// 审批的附件是顶层 files[]（不嵌在 request 下），form_data 走 multipart 嵌套哈希
// 申请人改单：仅「审批中且尚无人处理」时后端放行，改后重建审批链
export const updateApprovalRequest = (id, payload) =>
  http.patch(`${base()}/oa/approval_requests/${id}`, payload);

export const createApprovalRequestWithFiles = (payload, files) => {
  const fd = new FormData();
  fd.append('template_id', payload.template_id);
  if (payload.department_id) fd.append('department_id', payload.department_id);
  Object.entries(payload.form_data || {}).forEach(([k, v]) =>
    fd.append(`form_data[${k}]`, v ?? '')
  );
  files.forEach(f => fd.append('files[]', f));
  return http.post(`${base()}/oa/approval_requests`, fd);
};

// 我所在的部门：模板审批链含「部门主管」时要指定按哪个部门找主管
export const fetchMyDepartments = () =>
  cachedGet(`${base()}/org/memberships`, { params: { mine: 'true' } });

// ── 销售单据（商机/订单/报价/PI）──
// 四类单据的列表与详情走同一套形状，故收成一对按 kind 分发的函数
const RECORD_PATHS = {
  opportunity: 'crm/opportunities',
  order: 'crm/sales_orders',
  quote: 'crm/quotes',
  pi: 'crm/pis',
};

// 成员/团队列表：后端要求管理员权限，业务员会 403。
// 调用方要自己兜住失败（商机「筛选」弹层就靠它决定显示人名还是说明文案）。
export const fetchCrmMembers = () => cachedGet(`${base()}/crm/members`);
export const fetchCrmTeams = () => cachedGet(`${base()}/crm/teams`);

export const fetchRecords = (kind, params) =>
  cachedGet(`${base()}/${RECORD_PATHS[kind]}`, { params });

export const fetchRecord = (kind, id) =>
  cachedGet(`${base()}/${RECORD_PATHS[kind]}/${id}`);

// ── 产品与核价表 ──
export const fetchProducts = params =>
  cachedGet(`${base()}/crm/products`, { params });

// 后端按角色收口：业务员只拿得到非草稿版本
export const fetchPriceLists = productLine =>
  cachedGet(`${base()}/crm/price_lists`, {
    params: { product_line: productLine || undefined },
  });

export const fetchPriceList = id => cachedGet(`${base()}/crm/price_lists/${id}`);

// ── 目标与看板 ──
export const fetchMyTarget = year =>
  cachedGet(`${base()}/crm/my_target`, { params: { year } });

export const fetchTeamDashboard = params =>
  cachedGet(`${base()}/crm/team_dashboard`, { params });

// ── 知识库 ──
// filter=company 公司资料 / mine 我的文档；后端按板块部门可见性收口
export const fetchDocs = params =>
  cachedGet(`${base()}/crm/knowledge_docs`, { params });

export const fetchDoc = id => cachedGet(`${base()}/crm/knowledge_docs/${id}`);

// ── 考勤 ──
// index 返回当月记录 + 本人考勤组配置（上下班时间、是否校验地点/网络）
export const fetchAttendance = month =>
  cachedGet(`${base()}/crm/attendances`, { params: { month } });

// field=true 为外勤打卡：跳过地点/网络校验，标记外勤，不判迟到
export const clockAttendance = payload =>
  http.post(`${base()}/crm/attendances/clock`, payload);

// ── 工作台 ──
// home_stats = 本人待办计数 + 本周考勤；stats = 业绩看板（scope=mine 为个人口径）
export const fetchHomeStats = () => cachedGet(`${base()}/crm/home_stats`);

export const fetchStats = params =>
  cachedGet(`${base()}/crm/stats`, { params });

export const fetchScheduleEvents = params =>
  cachedGet(`${base()}/crm/schedule_events`, { params });

export const createScheduleEvent = schedule_event =>
  http.post(`${base()}/crm/schedule_events`, { schedule_event });

export const updateScheduleEvent = (id, schedule_event) =>
  http.patch(`${base()}/crm/schedule_events/${id}`, { schedule_event });

export const deleteScheduleEvent = id =>
  http.delete(`${base()}/crm/schedule_events/${id}`);

// 重复日程按「某一天」勾完成，故要带上这次发生的日期
export const toggleScheduleDone = (id, date) =>
  http.post(`${base()}/crm/schedule_events/${id}/toggle_done`, { date });
