<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import LeadCampaignsAPI from 'dashboard/api/crm/leadCampaigns';
import LeadsAPI from 'dashboard/api/crm/leads';
import OptionItemsAPI from 'dashboard/api/crm/optionItems';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import importYetiLogo from 'dashboard/assets/images/crm/importyeti.png';

// 新客开发：主动去找客户，而不是等客户上门。
//
// 第一步是「理想客户画像」——和同类产品最大的区别在喂给 AI 的料：
// 它们只能抓你的官网，我们喂的是真实成交数据（货卖到哪些国家、真卖出去的产品和均价）。
// 官网说的是我们想卖什么，订单说的是客户真的买了什么。
const { t } = useI18n();
const detailTab = ref('leads');
const campaigns = ref([]);
const current = ref(null);
const loading = ref(false);
const building = ref(false);
const creating = ref(false);
const showForm = ref(false);
// 有值 = 在改这个任务，没值 = 在新建。两种共用同一张表单，省得维护两份。
const editingId = ref(null);
const campaignDialog = ref(null);
const outcomesDialog = ref(null);

const form = ref({
  name: '',
  markets: [],
  productHint: '',
  targetCount: 60,
  screenCriteria: '',
  defaultCustomerGroup: '',
  autoRun: false,
  shared: true,
});

// 客户分组选项取自「客户设置」里配的那套（Crm::OptionItem），不另起一套枚举。
// 任务上选了哪个，这个任务建出来的客户就默认进哪个分组。
const groupOptions = ref([]);
const loadGroupOptions = async () => {
  try {
    const { data } = await OptionItemsAPI.get('customer_group');
    const rows = data?.payload || data || [];
    groupOptions.value = [
      { value: '', label: t('CRM.LEAD_CENTER_UI.CLAIM_GROUP_NONE') },
      ...rows
        .filter(r => r.code)
        .map(r => ({ value: r.code, label: r.name || r.code })),
    ];
  } catch {
    // 取不到就只留「不指定」，不挡着建任务。
    groupOptions.value = [
      { value: '', label: t('CRM.LEAD_CENTER_UI.CLAIM_GROUP_NONE') },
    ];
  }
};

const marketOptions = computed(() =>
  Object.entries(COUNTRY_LABELS).map(([value, label]) => ({ value, label }))
);

// 获客效果：从搜索词一路追到成交额。
//
// 同类工具的链路到「发出开发信」就断了，发出去之后成没成交它看不见；
// 线索建档之后人就进了同一个库，这条链对我们只是一条查询。
// 这张表同时是喂回给 AI 的料（下一轮生成关键词时带上），所以用得越久越准。
const outcomes = ref(null);
// 本月还能解锁几条。解锁是唯一会扣 Apollo 积分的动作，额度见 Crm::ApolloQuota。
const apolloQuota = ref({});
// 手上压着多少条没处理完的（上限见后端 Crm::Lead::HOLD_LIMIT）。
const heldCount = ref(0);
// 管理端的「团队概览」不在这个页面——它在数据看板里（2026-11-08 定）。
// 接口仍是 LeadCampaignsAPI.teamStats，口径见 Crm::LeadTeamStats。
const holdLimit = ref(0);
// 没设上限就什么都不显示——不限额的时候摆个「剩余 ∞」只是噪音。
const quotaLeft = computed(() => {
  const q = apolloQuota.value || {};
  if (q.user_left === null || q.user_left === undefined) return null;
  return { left: q.user_left, limit: q.user_limit };
});
const campaignSearchQuota = computed(() => current.value?.search_quota);
const campaignSearchRun = computed(() => current.value?.search_run || {});
const campaignSearchState = computed(() => {
  if (current.value?.status === 'QUEUED') return 'queued';
  if (current.value?.status === 'SEARCHING') return 'running';
  return (
    campaignSearchRun.value.state ||
    (current.value?.searched_at ? 'completed' : '')
  );
});
const campaignSearchStateLabel = computed(() => {
  const stages = {
    learning_keywords: 'LEARNING_KEYWORDS',
    collecting_companies: 'COLLECTING_COMPANIES',
    screening: 'SCREENING',
    saving_leads: 'SAVING_LEADS',
  };
  if (
    campaignSearchState.value === 'running' &&
    stages[campaignSearchRun.value.stage]
  ) {
    return t(`CRM.SEARCH_VISIBILITY.${stages[campaignSearchRun.value.stage]}`);
  }
  const keys = {
    queued: 'QUEUED',
    running: 'RUNNING',
    completed: 'COMPLETED',
    failed: 'FAILED',
  };
  const key = keys[campaignSearchState.value];
  return key ? t(`CRM.SEARCH_VISIBILITY.${key}`) : '';
});
const campaignSearchTime = computed(() => {
  const run = campaignSearchRun.value;
  const state = campaignSearchState.value;
  const [key, value] = {
    queued: ['QUEUED_AT', run.queued_at],
    running: ['STARTED_AT', run.started_at],
  }[state] || ['FINISHED_AT', run.finished_at || current.value?.searched_at];
  if (!value) return '';
  return t(`CRM.SEARCH_VISIBILITY.${key}`, {
    time: new Date(value).toLocaleString('zh-CN', { hour12: false }),
  });
});
const showOutcomes = ref(false);

const loadOutcomes = async () => {
  try {
    const { data } = await LeadCampaignsAPI.outcomes({});
    outcomes.value = data;
  } catch {
    // 效果表拉不到不影响主流程，静默即可。
  }
};

const outcomeSummary = computed(() => outcomes.value?.summary || null);
const learnedClaimed = computed(() => outcomes.value?.learned?.claimed || []);
const learnedRejected = computed(() => outcomes.value?.learned?.rejected || []);
// 从标记里归纳出的方向：倾向哪几类行业、排除哪几类、以及丢弃原因的分布。
// 摆出来是为了让人看得见系统学成了什么样——点错了一眼就能发现。
const directions = computed(() => outcomes.value?.directions || {});
const prefer = computed(() => Object.entries(directions.value.prefer || {}));
const avoid = computed(() => Object.entries(directions.value.avoid || {}));
const avoidReasons = computed(() =>
  Object.entries(directions.value.reasons || {})
);
const hasDirections = computed(
  () => prefer.value.length + avoid.value.length + avoidReasons.value.length > 0
);
// 判例一行怎么写：名字 · 行业 · 营收 · 门店 · 国家
const exampleLine = e =>
  [
    e.name,
    e.industry,
    e.revenue && `营收 ${e.revenue}`,
    e.retail > 0 && `${e.retail} 家门店`,
    e.country,
  ]
    .filter(Boolean)
    .join(' · ');
const wanRmb = n => (n >= 10000 ? `${Math.round(n / 10000)}万` : n);

const leads = ref([]);
const searching = ref(false);
const busyLeadId = ref(null);

// 切任务/切池子时，前一个请求可能比后一个晚回来，把列表盖成上一个任务的
// （2026-11-10：点进「医疗一体机」，标题是它、列表却是「数字标牌」那 119 条）。
// 每次取数发一个号，回来时对不上就丢弃。
let leadsRequestId = 0;

const loadLeads = async id => {
  leadsRequestId += 1;
  const req = leadsRequestId;
  leads.value = [];
  if (!id) return;
  try {
    const { data } = await LeadCampaignsAPI.leads(id);
    if (req !== leadsRequestId) return;
    leads.value = data.payload || [];
    heldCount.value = data.held_count || 0;
    holdLimit.value = data.hold_limit || 0;
  } catch {
    if (req === leadsRequestId) leads.value = [];
  }
};

const addMarket = v => {
  if (v && !form.value.markets.includes(v)) form.value.markets.push(v);
};
const removeMarket = v => {
  form.value.markets = form.value.markets.filter(x => x !== v);
};

const emptyForm = () => ({
  name: '',
  markets: [],
  productHint: '',
  targetCount: 60,
  screenCriteria: '',
  defaultCustomerGroup: '',
  autoRun: false,
  shared: true,
});

// 「额外筛选条件」和「建档分组」本来就是看到结果再调的东西，不能只在建任务时设一次。
const openEdit = c => {
  editingId.value = c.id;
  form.value = {
    name: c.name || '',
    markets: [...(c.target_markets || [])],
    productHint: c.product_hint || '',
    targetCount: c.target_count || 60,
    screenCriteria: c.screen_criteria || '',
    defaultCustomerGroup: c.default_customer_group || '',
    autoRun: Boolean(c.auto_run),
    shared: c.shared !== false,
  };
  showForm.value = true;
};

const openCreate = () => {
  editingId.value = null;
  form.value = emptyForm();
  showForm.value = true;
};

const campaignPayload = () => ({
  name: form.value.name.trim(),
  target_markets: form.value.markets,
  product_hint: form.value.productHint.trim() || null,
  // 业务员自己补的初筛条件。通用标准覆盖不了的场景（「只要有自己门店的」
  // 「排掉纯线上培训」）只有跑业务的人知道，所以留一个口子让他写。
  screen_criteria: form.value.screenCriteria.trim() || null,
  default_customer_group: form.value.defaultCustomerGroup || null,
  // 自动续挖：关键词底下的公司挖不完，但手动按钮没人天天点。
  auto_run: form.value.autoRun,
  shared: form.value.shared,
  target_count: Number(form.value.targetCount) || 60,
});

const saveCampaign = async () => {
  if (!form.value.name.trim()) return useAlert('给这次拓客起个名字');
  if (!form.value.markets.length) return useAlert('至少选一个目标市场');
  creating.value = true;
  try {
    const { data } = await LeadCampaignsAPI.update(editingId.value, {
      campaign: campaignPayload(),
    });
    const i = campaigns.value.findIndex(c => c.id === data.id);
    if (i >= 0) campaigns.value[i] = data;
    if (current.value?.id === data.id) current.value = data;
    showForm.value = false;
    editingId.value = null;
    useAlert(t('CRM.LEAD_CENTER_UI.EDIT_SAVED'));
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    creating.value = false;
  }
  return undefined;
};

const createCampaign = async () => {
  if (!form.value.name.trim()) return useAlert('给这次拓客起个名字');
  if (!form.value.markets.length) return useAlert('至少选一个目标市场');
  creating.value = true;
  try {
    const { data } = await LeadCampaignsAPI.create({
      campaign: campaignPayload(),
    });
    campaigns.value.unshift(data);
    current.value = data;
    showForm.value = false;
    form.value = emptyForm();
  } catch (e) {
    useAlert(e?.response?.data?.error || '建任务失败');
  } finally {
    creating.value = false;
  }
  return undefined;
};

const buildProfile = async () => {
  if (!current.value) return;
  building.value = true;
  try {
    const { data } = await LeadCampaignsAPI.buildProfile(current.value.id);
    current.value = data;
    const i = campaigns.value.findIndex(c => c.id === data.id);
    if (i >= 0) campaigns.value[i] = data;
    useAlert('客户画像已生成');
  } catch (e) {
    useAlert(e?.response?.data?.error || '画像生成失败');
  } finally {
    building.value = false;
  }
};

// 画像里每一条标明来源：有成交数据撑着的，和模型自己推的，分开摆。
// 拿一个凭空推出来的「目标行业」去发开发信，错的不只是一封信。
const personaRows = computed(() => {
  const p = current.value?.profile || {};
  const LABELS = {
    decision_roles: '决策人角色',
    industries: '目标行业',
    company_size: '公司规模',
    geography: '地理重点',
  };
  return Object.keys(LABELS)
    .filter(k => p[k])
    .map(k => ({
      key: k,
      label: LABELS[k],
      value: typeof p[k] === 'object' ? p[k].value : p[k],
      fromData: typeof p[k] === 'object' && p[k].evidence === 'data',
    }));
});

// Apollo 企业库词表里查不到的搜索词。跑完记在任务上，这里摆出来——
// 不摆的话这些词只会静静地产出 0 条线索，没人知道为什么。
const deadKeywords = computed(() => current.value?.dead_keywords || []);

// 搜索词的评级（后端按真实产出算，见 Crm::KeywordGrade）。
// 好词排前面、废词划掉排最后——一个任务攒到四五十个词之后，
// 人已经分不清哪些还在干活，不分级就只能靠猜。
const GRADE_ORDER = ['proven', 'usable', 'weak', 'dead', 'new'];
const GRADE_STYLE = {
  proven: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
  usable: 'border-n-weak bg-n-slate-2 text-n-slate-12',
  weak: 'border-n-weak bg-n-slate-2 text-n-slate-10',
  dead: 'border-dashed border-n-weak text-n-slate-9 line-through',
  new: 'border-dashed border-n-weak bg-n-slate-1 text-n-slate-11',
};
const gradeLabel = g =>
  t(`CRM.LEAD_CENTER_UI.GRADE_${(g || 'new').toUpperCase()}`);
const gradeStyle = g => GRADE_STYLE[g] || GRADE_STYLE.new;
const gradeRank = g => {
  const i = GRADE_ORDER.indexOf(g || 'new');
  return i === -1 ? GRADE_ORDER.length : i;
};

const keywordsByMarket = computed(() => {
  const out = {};
  (current.value?.keywords || []).forEach(k => {
    (out[k.market] = out[k.market] || []).push(k);
  });
  Object.values(out).forEach(list =>
    list.sort((a, b) => gradeRank(a.grade) - gradeRank(b.grade))
  );
  return out;
});

const facts = computed(() => current.value?.facts || {});

// ── 线索池 ──

// 搜索一次要跑三五分钟（每个关键词一次 Apollo 调用，再逐家公司抽联系人），
// 所以按钮要一直转，不能让人以为卡死了。
// 后端排队跑（一次三到五分钟，在请求里等必然被 15 秒超时掐断），这里轮询任务状态。
// 轮询而不是一直转圈：页面刷新、换台电脑打开，照样能接着看进度。
const SEARCH_POLL_MS = 8000;
const SEARCH_POLL_MAX = 60;
const ACTIVE_SEARCH_STATUSES = ['QUEUED', 'SEARCHING'];
const searchClock = ref(Date.now());
const searchPollPaused = ref(false);
const searchSubmitting = ref(false);
const searchRetryAvailable = computed(() => {
  if (
    !ACTIVE_SEARCH_STATUSES.includes(current.value?.status) ||
    campaignSearchQuota.value?.allowed === false
  )
    return false;
  const retryAt = current.value.search_run?.retry_after
    ? new Date(current.value.search_run.retry_after).getTime()
    : new Date(current.value.updated_at).getTime() + 15 * 60 * 1000;
  return retryAt <= searchClock.value;
});
const searchRefreshOnly = computed(
  () =>
    ACTIVE_SEARCH_STATUSES.includes(current.value?.status) &&
    !searchRetryAvailable.value
);
const searchButtonLoading = computed(
  () =>
    searchSubmitting.value || (searching.value && !searchRetryAvailable.value)
);
const searchButtonLabel = computed(() => {
  if (
    searchRetryAvailable.value ||
    current.value?.search_run?.state === 'failed'
  ) {
    return t('CRM.LEAD_CENTER_UI.SEARCH_RETRY');
  }
  if (searchPollPaused.value && searchRefreshOnly.value)
    return t('CRM.LEAD_CENTER_UI.SEARCH_REFRESH');
  if (current.value?.status === 'QUEUED')
    return t('CRM.LEAD_CENTER_UI.SEARCH_QUEUED');
  return searching.value
    ? t('CRM.LEAD_CENTER_UI.TEXT_031')
    : t('CRM.LEAD_CENTER_UI.TEXT_032');
});
let searchTimer = null;
let searchPollId = 0;
const searchClockTimer = setInterval(() => {
  searchClock.value = Date.now();
}, 30000);

const stopSearchPoll = () => {
  searchPollId += 1;
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = null;
  searching.value = false;
  searchSubmitting.value = false;
};

const updateSearchCampaign = campaign => {
  const index = campaigns.value.findIndex(c => c.id === campaign.id);
  if (index >= 0)
    campaigns.value[index] = { ...campaigns.value[index], ...campaign };
  if (current.value?.id === campaign.id)
    current.value = { ...current.value, ...campaign };
};

const pollSearch = async (id, tries = 0, pollId = searchPollId) => {
  if (pollId !== searchPollId || current.value?.id !== id) return undefined;
  if (tries >= SEARCH_POLL_MAX) {
    stopSearchPoll();
    searchPollPaused.value = true;
    return undefined;
  }
  try {
    const { data } = await LeadCampaignsAPI.show(id);
    if (pollId !== searchPollId || current.value?.id !== id) return undefined;
    const campaign = data.payload || data;
    updateSearchCampaign(campaign);
    searchClock.value = Date.now();
    if (!ACTIVE_SEARCH_STATUSES.includes(campaign.status)) {
      stopSearchPoll();
      searchPollPaused.value = false;
      if (campaign.last_error) useAlert(campaign.last_error);
      await loadLeads(id);
      loadOutcomes();
      return undefined;
    }
    searching.value = true;
  } catch {
    // 网络失败不等于任务结束，下一轮继续查看。
  }
  if (pollId === searchPollId && current.value?.id === id) {
    searchTimer = setTimeout(
      () => pollSearch(id, tries + 1, pollId),
      SEARCH_POLL_MS
    );
  }
  return undefined;
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await LeadCampaignsAPI.get({});
    campaigns.value = data.payload || [];
    apolloQuota.value = data.apollo_quota || {};
    // 默认选中第一个任务，并把它的线索一起拉回来——
    // 不拉的话进页面看到的永远是「点右上角开始找」，哪怕线索早就搜好了。
    if (!current.value && campaigns.value.length) {
      current.value = campaigns.value[0];
      await loadLeads(current.value.id);
      if (ACTIVE_SEARCH_STATUSES.includes(current.value?.status)) {
        searching.value = true;
        pollSearch(current.value.id);
      }
    }
  } catch {
    useAlert('拓客任务加载失败');
  } finally {
    loading.value = false;
  }
};

const runSearch = async () => {
  if (!current.value || searchButtonLoading.value) return;
  const id = current.value.id;
  const refreshOnly = searchRefreshOnly.value;
  stopSearchPoll();
  const pollId = searchPollId;
  searchPollPaused.value = false;
  searching.value = true;
  if (refreshOnly) {
    pollSearch(id, 0, pollId);
    return;
  }
  searchSubmitting.value = true;
  try {
    const { data } = await LeadCampaignsAPI.search(id);
    if (pollId !== searchPollId || current.value?.id !== id) return;
    updateSearchCampaign({ id, ...data });
    pollSearch(id, 0, pollId);
  } catch (error) {
    if (pollId !== searchPollId || current.value?.id !== id) return;
    searching.value = false;
    useAlert(
      error?.response?.data?.error || t('CRM.LEAD_CENTER_UI.SEARCH_FAILED')
    );
    // 另一个窗口已启动、或旧 worker 仍在工作时，只恢复观察，不再次入队。
    if (error?.response?.status === 409) pollSearch(id, 0, pollId);
  } finally {
    if (pollId === searchPollId) searchSubmitting.value = false;
  }
};

onBeforeUnmount(() => {
  clearInterval(searchClockTimer);
  stopSearchPoll();
});

// 丢弃原因。点一下就走，不打字——原因不是给人看的记录，
// 是给初筛学的方向：没有原因，系统只能学到「这家不要」，学不到「这类不要」。
const DISCARD_REASONS = [
  'RIVAL',
  'SIZE',
  'CATEGORY',
  'EXISTING',
  'COUNTRY',
  'UNREACHABLE',
  'OTHER',
];
const discardMenuFor = ref(null);

const replaceLead = updated => {
  const i = leads.value.findIndex(l => l.id === updated.id);
  if (i >= 0) leads.value[i] = { ...leads.value[i], ...updated };
};

// 解锁扣 credits，所以一条一条来，不做批量。
const unlockLead = async lead => {
  busyLeadId.value = lead.id;
  try {
    const { data } = await LeadsAPI.unlock(lead.id);
    replaceLead(data);
  } catch (e) {
    useAlert(e?.response?.data?.error || '解锁失败');
  } finally {
    busyLeadId.value = null;
  }
};

// 从共享池领取。线索不归挖它的人，谁领归谁——保护期内别人看不见也领不走
// （见 Crm::LeadClaim）。解锁和建档会自动领取，这个按钮给「先占住再慢慢看」用。
const takeLead = async lead => {
  busyLeadId.value = lead.id;
  try {
    const { data } = await LeadsAPI.take(lead.id);
    replaceLead(data);
    useAlert(data.message || '已领取');
    heldCount.value += 1;
  } catch (e) {
    useAlert(e?.response?.data?.error || '领取失败');
  } finally {
    busyLeadId.value = null;
  }
};

// 放回池子：我暂时跟不了。和丢弃不同——丢弃是「这家不是买家」，会喂给 AI 初筛。
const releaseLead = async lead => {
  busyLeadId.value = lead.id;
  try {
    const { data } = await LeadsAPI.release(lead.id);
    replaceLead(data);
    heldCount.value = Math.max(0, heldCount.value - 1);
  } catch (e) {
    useAlert(e?.response?.data?.error || '放回失败');
  } finally {
    busyLeadId.value = null;
  }
};

// 建档和丢弃都会改效果表（建档进了成交链路、丢弃进了 AI 判例），点完就刷。
const claimLead = async lead => {
  busyLeadId.value = lead.id;
  try {
    const { data } = await LeadsAPI.claim(lead.id);
    replaceLead(data);
    useAlert(
      data.duplicate
        ? `这家已经在库里：${data.customer_name}`
        : `已建档：${data.customer_name}`
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || '建档失败');
  } finally {
    busyLeadId.value = null;
    loadOutcomes();
  }
};

const discardLead = async (lead, reason = null) => {
  discardMenuFor.value = null;
  busyLeadId.value = lead.id;
  try {
    // 丢的是这家公司，不是这一个人——同公司的几条一起丢，
    // 否则列表里会剩下同一家的另外两个联系人，等于没丢掉。
    const key = lead.domain || lead.company_name;
    const siblings = leads.value.filter(
      x =>
        x.id !== lead.id &&
        x.status !== 'CLAIMED' &&
        (x.domain || x.company_name) === key
    );
    const { data } = await LeadsAPI.discard(lead.id, reason);
    replaceLead(data);
    await Promise.all(
      siblings.map(x =>
        LeadsAPI.discard(x.id, reason).then(r => replaceLead(r.data))
      )
    );
  } finally {
    busyLeadId.value = null;
    loadOutcomes();
  }
};

// 共享池视图：'pool' 池子里能领的 / 'mine' 我领的 / null 看某个任务。
// 这两个是业务员每天真正用的入口——任务是「怎么挖」，池子才是「今天跟谁」。
const POOL_VIEWS = [
  { key: 'pool', label: 'CRM.LEAD_CENTER_UI.POOL_SHARED' },
  { key: 'mine', label: 'CRM.LEAD_CENTER_UI.POOL_MINE' },
];
const poolView = ref('pool');
const selectPool = async scope => {
  stopSearchPoll();
  searchPollPaused.value = false;
  leadsRequestId += 1;
  const req = leadsRequestId;
  poolView.value = scope;
  current.value = null;
  leads.value = [];
  try {
    const { data } = await LeadCampaignsAPI.pool(scope);
    if (req !== leadsRequestId) return;
    leads.value = data.payload || [];
    heldCount.value = data.held_count || 0;
    holdLimit.value = data.hold_limit || 0;
  } catch {
    if (req === leadsRequestId) leads.value = [];
  }
};

const selectCampaign = c => {
  stopSearchPoll();
  poolView.value = null;
  current.value = c;
  searchPollPaused.value = false;
  loadLeads(c.id);
  if (ACTIVE_SEARCH_STATUSES.includes(c.status)) {
    searching.value = true;
    pollSearch(c.id);
  }
};

// 行业代码认定「不可能是买家」的（出版、广电、人力中介这些）默认折叠。
// 只是不显示——不删不改，点一下就全回来。黑名单在后端（Crm::NaicsLabel::NOT_BUYERS），
// 前端只认 not_buyer 这个布尔，免得两边各写一份走偏。
const showNotBuyers = ref(false);

const liveLeads = computed(() =>
  leads.value.filter(l => l.status !== 'DISCARDED')
);
// 已建档的不折：人工都认了这条、建成客户了，系统再按行业把它藏起来说不过去。
const foldedLeads = computed(() =>
  liveLeads.value.filter(l => l.not_buyer && l.status !== 'CLAIMED')
);
// 折叠的那几类是什么行业，直接写在展开按钮上——不说清楚就等于让人猜折了什么。
const foldedKinds = computed(() => {
  const kinds = [
    ...new Set(foldedLeads.value.map(l => l.industry).filter(Boolean)),
  ];
  // 最多列四个，还有更多就加个「等」——列不全又不说，看着像只折了这几类。
  return kinds.slice(0, 4).join('、') + (kinds.length > 4 ? ' 等' : '');
});
// 按「现在能不能发信」筛。业务员打开池子第一个问题就是这个，
// 而官网邮箱是不花 Apollo 额度拿到的（见 Crm::SiteContactFinder），
// 其中 sales@ / 真人邮箱（a.schmidt@ 这种）质量接近解锁出来的，info@ 那类只能算兜底。
const MAIL_FILTERS = [
  { key: 'all', label: 'MAIL_FILTER_ALL' },
  { key: 'any', label: 'MAIL_FILTER_ANY' },
  { key: 'good', label: 'MAIL_FILTER_GOOD' },
];
const mailFilter = ref('all');
const GOOD_MAIL =
  /^(sales|vertrieb|ventas|commercial|enquir|inquir|insidesales)|^[a-z]+\.[a-z]+@/i;
const mailsOf = l => (l.bg && l.bg.emails) || [];
const matchesMailFilter = l => {
  if (mailFilter.value === 'all') return true;
  const mails = mailsOf(l);
  if (mailFilter.value === 'any') return mails.length > 0;
  return mails.some(m => GOOD_MAIL.test(m));
};

const visibleLeads = computed(() => {
  const base = showNotBuyers.value
    ? liveLeads.value
    : liveLeads.value.filter(
        l => !new Set(foldedLeads.value.map(x => x.id)).has(l.id)
      );
  return base.filter(matchesMailFilter);
});
const leadPage = ref(1);
const leadPageSize = 10;
const leadList = ref(null);
// 官网邮箱点一下就复制——业务员拿到它就是要贴进收件人框，
// 让他手动选中一串 sales@xxx.de 纯属添堵。
const copyEmail = async mail => {
  try {
    await navigator.clipboard.writeText(mail);
    useAlert(t('CRM.LEAD_CENTER_UI.BG_EMAIL_COPIED', { mail }));
  } catch {
    useAlert(t('CRM.LEAD_CENTER_UI.BG_EMAIL_COPY_FAILED'));
  }
};

// 按公司归并。一家公司有几个采购就占几行的话，首页十行只剩七家公司——
// Newegg 一家吃掉三行（用户 2026-11-08 反馈）。
// 所以分页按**公司**算，同一家的后续联系人只留人名那一行，公司信息不重复。
const leadGroups = computed(() => {
  const groups = [];
  const seen = new Map();
  visibleLeads.value.forEach(l => {
    const key = l.domain || l.company_name || `#${l.id}`;
    if (!seen.has(key)) {
      seen.set(key, groups.length);
      groups.push([]);
    }
    groups[seen.get(key)].push(l);
  });
  return groups;
});
const leadPageCount = computed(() =>
  Math.max(1, Math.ceil(leadGroups.value.length / leadPageSize))
);
const pagedLeads = computed(() => {
  const start = (leadPage.value - 1) * leadPageSize;
  return leadGroups.value
    .slice(start, start + leadPageSize)
    .flatMap(rows => rows.map((l, i) => ({ ...l, head: i === 0 })));
});

watch(
  () => current.value?.id,
  () => {
    leadPage.value = 1;
  }
);
watch(leadPageCount, pageCount => {
  leadPage.value = Math.min(leadPage.value, pageCount);
});
// 折叠的这些 AI 都判了「不是买家」，排序本来就在最末尾。
// 点「展开看看」还停在第一页的话，等于什么都没看见——直接翻到它们那一页去。
watch(showNotBuyers, open => {
  if (!open) {
    leadPage.value = 1;
    return;
  }
  const folded = new Set(foldedLeads.value.map(l => l.id));
  const first = visibleLeads.value.findIndex(l => folded.has(l.id));
  leadPage.value = first < 0 ? 1 : Math.floor(first / leadPageSize) + 1;
});
watch(leadPage, () => {
  if (leadList.value) leadList.value.scrollTop = 0;
});

// 外部情报跳转。这几个平台都**接不进系统**，但人工看一眼很值：
//   · ImportYeti —— 美国海关提单。Apollo 只能说「这家是电子批发商」，
//     提单能说「这家去年真的进了 12 柜平板」。有官方 API（搜索免费、详情 $0.02），
//     接是能接的，先放链接让人验证值不值。
//   · Meta 广告库 —— 网页版免费且不用登录，但**商业广告没有 API**
//     （Meta 只对政治广告开放 API，欧盟/英国因 DSA 才全开），所以只能跳转。
//   · 领英 —— Sales Navigator 的 API 不接受新合作方，爬又违反协议，同样只能跳转。
// ⚠️ ImportYeti 的公司页是 /company/{slug}（文档确认），但它家 CDN 挡了所有
// 非浏览器请求，搜索页的格式没法在这边验证。点了要是 404，把真实地址发我改这一行。
const slugify = name =>
  String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

// 外部情报入口。logo 用真实的：ImportYeti 的存在本地（外链国外站点的图在国内常加载不出来，
// 图裂比没图更糟），Facebook 用图标集里的 i-logos-facebook，和领英那个同一套。
const externalLookups = l => {
  const name = l.company_name;
  if (!name) return [];
  return [
    // ImportYeti 只有**美国**海关的进口记录。挂在德国法国公司上点过去必然是空页，
    // 所以非美国市场不显示这个入口。
    ...(l.market === 'USA' || l.country === 'USA'
      ? [
          {
            key: 'importyeti',
            img: importYetiLogo,
            label: t('CRM.LEAD_CENTER_UI.LOOKUP_IMPORTYETI'),
            hint: t('CRM.LEAD_CENTER_UI.LOOKUP_IMPORTYETI_HINT'),
            href: `https://www.importyeti.com/company/${slugify(name)}`,
          },
        ]
      : []),
    {
      key: 'adlib',
      icon: 'i-logos-facebook',
      label: t('CRM.LEAD_CENTER_UI.LOOKUP_ADLIB'),
      hint: t('CRM.LEAD_CENTER_UI.LOOKUP_ADLIB_HINT'),
      href: `https://www.facebook.com/ads/library/?active_status=all&ad_type=all&country=ALL&q=${encodeURIComponent(name)}&search_type=keyword_unordered`,
    },
  ];
};

// 官网能不能打开。背调抓过之后才知道——451 是地区封锁、403 是反爬，
// 这两种业务员点进去同样是「无法访问此网站」。提前标出来省一次白点。
const siteIssue = l => {
  const code = l.bg && l.bg.site_status;
  if (code && code >= 400) {
    return {
      blocked: true,
      label: t('CRM.LEAD_CENTER_UI.SITE_BLOCKED', { code }),
    };
  }
  if (l.bg && l.bg.status === 'no_site') {
    return { blocked: false, label: t('CRM.LEAD_CENTER_UI.SITE_DEAD') };
  }
  return null;
};

// 搜索阶段 Apollo 白给的公司资料。实测 98 家样本：领英 100%、电话 71%、
// 营收 53%、门店数 13%。电话和领英最实用——解锁邮箱要花 credits，这两个不要钱，
// 业务员拿着就能打过去。
const orgFacts = l => {
  const o = l.org || {};
  return [
    o.revenue && {
      key: 'revenue',
      text: t('CRM.LEAD_CENTER_UI.ORG_REVENUE', { value: o.revenue }),
    },
    o.retail > 0 && {
      key: 'retail',
      text: t('CRM.LEAD_CENTER_UI.ORG_RETAIL', { count: o.retail }),
    },
    o.listed && { key: 'listed', text: t('CRM.LEAD_CENTER_UI.ORG_LISTED') },
    o.phone && {
      key: 'phone',
      text: o.phone,
      href: `tel:${o.phone.replace(/\s/g, '')}`,
      icon: 'i-lucide-phone',
    },
    o.linkedin && {
      key: 'linkedin',
      text: t('CRM.LEAD_CENTER_UI.ORG_LINKEDIN'),
      href: o.linkedin,
      icon: 'i-logos-linkedin-icon',
    },
  ].filter(Boolean);
};

// 一键 AI 背调：真去抓这家公司的官网读一遍，再配上 Apollo 企业库。
//
// 和 AI 初筛的区别值得说清楚：初筛只看公司名和域名猜，一屏一百条全靠它排序；
// 背调是对单条下狠功夫——实测近 30 秒。所以初筛自动跑、背调人工点。
// 结果存回线索（同公司的几个联系人共用），刷新页面还在，不会白等第二次。
const bgBusyId = ref(null);

// 背调改成异步：点完立刻返回，后台跑，这边轮询等结果。
// 同步跑会占着 Web 线程 20~30 秒等外国网站（生产一共 15 个线程），
// 五六个人同时点就把系统拖慢了——而且让人盯着转圈半分钟本来就不该。
const BG_POLL_EVERY = 4000;
const BG_POLL_MAX = 30; // 4 秒 × 30 ≈ 2 分钟，超了就不等了

// 同一家公司的其它联系人后端也盖了章，前端跟着一起更新，省一次重查。
const spreadBg = data => {
  leads.value = leads.value.map(l =>
    l.id !== data.id && l.company_name && l.company_name === data.company_name
      ? { ...l, bg: data.bg }
      : l
  );
};

const pollBg = async id => {
  for (let i = 0; i < BG_POLL_MAX; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise(r => setTimeout(r, BG_POLL_EVERY));
    try {
      // eslint-disable-next-line no-await-in-loop
      const { data } = await LeadsAPI.show(id);
      replaceLead(data);
      if (data.bg) {
        spreadBg(data);
        return;
      }
      if (!data.bg_running) return;
    } catch {
      return; // 查不动就别一直试，页面刷新后状态也还在
    }
  }
};

const runBgCheck = async lead => {
  bgBusyId.value = lead.id;
  try {
    const { data } = await LeadsAPI.bgCheck(lead.id);
    replaceLead(data);
    await pollBg(lead.id);
  } catch (e) {
    useAlert(e?.response?.data?.error || t('CRM.LEAD_CENTER_UI.BG_FAILED'));
  } finally {
    bgBusyId.value = null;
  }
};

// 线索第二行「人名 · 职位 · 邮箱 · 搜索词」：按实际有的字段拼成数组，
// 分隔符交给渲染时插在中间——写死在文案里的话，
// 没有联系人的那几条就会以一个孤零零的「·」开头。
const leadMeta = l =>
  [
    l.person_name
      ? { text: l.person_name, tone: '' }
      : // 没搜到联系人的占 yes 的 28%（2026-11-08 实测）。挖出来也打不着，
        // 得在行上直说——以前只能点进去才发现，而且它们按分数照样排在前面。
        { text: t('CRM.LEAD_CENTER_UI.TEXT_076'), tone: 'text-n-slate-9' },
    l.title && { text: l.title, tone: '' },
    l.email
      ? { text: l.email, tone: 'text-n-teal-11' }
      : l.email_available && {
          text: t('CRM.LEAD_CENTER_UI.TEXT_042'),
          tone: 'text-n-slate-9',
        },
    l.matched_keyword && {
      // apollo_tag 是企业库里实际命中的标签。和搜索词不一样的时候要摆出来——
      // 「搜索词 toys and games wholesaler」其实是按 toys 搜的，差别决定了精不精准。
      text:
        l.apollo_tag && l.apollo_tag !== l.matched_keyword
          ? t('CRM.LEAD_CENTER_UI.TEXT_072', {
              keyword: l.matched_keyword,
              tag: l.apollo_tag,
            })
          : t('CRM.LEAD_CENTER_UI.TEXT_043', { keyword: l.matched_keyword }),
      tone: 'text-n-slate-9',
    },
  ].filter(Boolean);

// 已经有人在跟的公司。光写「已是我们客户」不够——业务员真正要知道的是
// **这是谁的客户**，否则照样发开发信撞到同事头上。归属人为空的是公海客户。
const dupLabel = l => {
  if (!l.dup_owner_name) return t('CRM.LEAD_CENTER_UI.TEXT_041');
  return t('CRM.LEAD_CENTER_UI.TEXT_074', { name: l.dup_owner_name });
};

// 官网链接由后端算（见 Crm::SiteUrl）：Apollo 存的是 http://www.xxx，
// 前端自己拼会把每一条都拼成浏览器要拦的 http 链接。
const siteHref = l => l.site_url || `https://${l.domain}`;

// 关键词写的是哪国语言。原来直接把 locale 代码（en / de_DE）摆在市场名后面，
// 没人看得懂，而且「德国 · en」看着像出错——其实是故意用英文品类词搜德国市场
// （进口商对外介绍自己常用英文）。所以翻成中文，并且标出是不是当地语言。
const LOCALE_NAMES = {
  en: '英文',
  de: '德语',
  fr: '法语',
  it: '意大利语',
  es: '西班牙语',
  nl: '荷兰语',
  sv: '瑞典语',
  pt: '葡萄牙语',
  tr: '土耳其语',
  ko: '韩语',
  ja: '日语',
  zh: '中文',
};
// 哪些市场说哪种语言——用来判断这批关键词是「当地话」还是「英文通用词」。
const MARKET_LOCAL_LANG = {
  GERMANY: 'de',
  AUSTRIA: 'de',
  SWITZERLAND: 'de',
  FRANCE: 'fr',
  ITALY: 'it',
  SPAIN: 'es',
  MEXICO: 'es',
  CHILE: 'es',
  NETHERLANDS: 'nl',
  SWEDEN: 'sv',
  PORTUGAL: 'pt',
  BRAZIL: 'pt',
  TURKEY: 'tr',
  SOUTH_KOREA: 'ko',
  JAPAN: 'ja',
};
const localeNote = (market, locale) => {
  const lang = String(locale || '')
    .split(/[-_]/)[0]
    .toLowerCase();
  const name = LOCALE_NAMES[lang];
  if (!name) return '';
  const local = MARKET_LOCAL_LANG[market];
  // 本来就说英语的市场（美国、英国）不用多嘴说「英文关键词」。
  if (!local) return lang === 'en' ? '' : name;
  return lang === local ? `${name}（当地语言）` : `${name}关键词`;
};

const marketLabel = m => COUNTRY_LABELS[m] || m;

watch(showForm, open => {
  if (open) campaignDialog.value.open();
  else campaignDialog.value.close();
});
watch(showOutcomes, open => {
  if (open) outcomesDialog.value.open();
  else outcomesDialog.value.close();
});

onMounted(() => {
  load();
  loadOutcomes();
  loadGroupOptions();
});
</script>

<template>
  <div
    class="flex h-full w-full flex-col overflow-hidden rounded-3xl border backdrop-blur-2xl backdrop-saturate-150 bg-n-solid-1/80 border-n-weak/70 shadow-wintouch-glass"
  >
    <header
      class="flex shrink-0 flex-wrap items-center justify-between gap-4 border-b border-n-weak px-5 py-4 sm:px-8"
    >
      <div class="min-w-0">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('CRM.LEAD_CENTER_UI.TEXT_001') }}
        </h1>
        <p class="mb-0 mt-1 text-label-small leading-relaxed text-n-slate-11">
          {{ t('CRM.LEAD_CENTER_UI.TEXT_002') }}
        </p>
      </div>
      <Button
        :label="t('CRM.LEAD_CENTER_UI.TEXT_003')"
        icon="i-lucide-plus"
        size="sm"
        class="shrink-0 !rounded-xl !bg-[#ffca35] !text-[#202427]"
        @click="openCreate"
      />
    </header>
    <div class="min-h-0 flex-1 overflow-hidden">
      <div
        class="mx-auto flex h-full min-h-0 w-full max-w-screen-2xl flex-col gap-4 px-5 py-4 sm:px-8"
      >
        <!-- 建任务 -->
        <Dialog
          ref="campaignDialog"
          :title="
            editingId
              ? t('CRM.LEAD_CENTER_UI.EDIT_TITLE')
              : t('CRM.LEAD_CENTER_UI.TEXT_003')
          "
          width="3xl"
          overflow-y-auto
          :show-confirm-button="false"
          :show-cancel-button="false"
          @close="showForm = false"
        >
          <div class="flex flex-col gap-4">
            <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
              <Input
                v-model="form.name"
                :label="t('CRM.LEAD_CENTER_UI.TEXT_018')"
                :placeholder="t('CRM.LEAD_CENTER_UI.TEXT_019')"
              />
              <Input
                v-model="form.productHint"
                :label="t('CRM.LEAD_CENTER_UI.TEXT_020')"
                :placeholder="t('CRM.LEAD_CENTER_UI.TEXT_021')"
              />
              <Input
                v-model="form.targetCount"
                :label="t('CRM.LEAD_CENTER_UI.TEXT_022')"
                placeholder="60"
              />
            </div>
            <label
              class="flex items-start gap-2.5 rounded-xl border border-n-weak p-3"
            >
              <input
                v-model="form.autoRun"
                type="checkbox"
                class="mt-0.5 size-4 shrink-0 accent-[#ffca35]"
              />
              <span class="min-w-0">
                <span class="block text-label text-n-slate-12">{{
                  t('CRM.LEAD_CENTER_UI.AUTO_RUN_LABEL')
                }}</span>
                <span class="block text-label-small text-n-slate-10">{{
                  t('CRM.LEAD_CENTER_UI.AUTO_RUN_HINT')
                }}</span>
              </span>
            </label>
            <!-- 挖到的线索进不进共享池。不勾的只有负责人自己看得见、领得走。 -->
            <label
              class="flex items-start gap-2.5 rounded-xl border border-n-weak p-3"
            >
              <input
                v-model="form.shared"
                type="checkbox"
                class="mt-0.5 size-4 shrink-0 accent-[#ffca35]"
              />
              <span class="min-w-0">
                <span class="block text-label text-n-slate-12">{{
                  t('CRM.LEAD_CENTER_UI.SHARED_LABEL')
                }}</span>
                <span class="block text-label-small text-n-slate-10">{{
                  t('CRM.LEAD_CENTER_UI.SHARED_HINT')
                }}</span>
              </span>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-label text-n-slate-12">{{
                t('CRM.LEAD_CENTER_UI.CLAIM_GROUP_LABEL')
              }}</span>
              <SelectCard
                v-model="form.defaultCustomerGroup"
                :options="groupOptions"
                block
              />
              <span class="text-label-small text-n-slate-10">{{
                t('CRM.LEAD_CENTER_UI.CLAIM_GROUP_HINT')
              }}</span>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-label text-n-slate-12">{{
                t('CRM.LEAD_CENTER_UI.CRITERIA_LABEL')
              }}</span>
              <textarea
                v-model="form.screenCriteria"
                rows="2"
                class="reset-base w-full resize-y rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-slate-6 focus:outline-none"
                :placeholder="t('CRM.LEAD_CENTER_UI.CRITERIA_PLACEHOLDER')"
              />
              <span class="text-label-small text-n-slate-10">{{
                t('CRM.LEAD_CENTER_UI.CRITERIA_HINT')
              }}</span>
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-label text-n-slate-12">{{
                t('CRM.LEAD_CENTER_UI.TEXT_023')
              }}</span>
              <SelectCard
                :options="marketOptions"
                block
                @update:model-value="addMarket"
              />
              <div
                v-if="form.markets.length"
                class="flex flex-wrap gap-1.5 mt-1"
              >
                <span
                  v-for="m in form.markets"
                  :key="m"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-label-small bg-n-slate-3 text-n-slate-12 rounded-full"
                >
                  {{ marketLabel(m) }}
                  <button
                    type="button"
                    class="reset-base"
                    @click="removeMarket(m)"
                  >
                    <Icon icon="i-lucide-x" class="size-3" />
                  </button>
                </span>
              </div>
            </label>
            <div class="flex gap-2">
              <Button
                :label="
                  editingId
                    ? t('CRM.LEAD_CENTER_UI.EDIT_SAVE')
                    : t('CRM.LEAD_CENTER_UI.TEXT_024')
                "
                size="sm"
                class="!rounded-xl !bg-[#ffca35] !text-[#202427]"
                :is-loading="creating"
                @click="editingId ? saveCampaign() : createCampaign()"
              />
              <Button
                :label="t('CRM.LEAD_CENTER_UI.TEXT_025')"
                size="sm"
                variant="outline"
                color="slate"
                @click="showForm = false"
              />
            </div>
          </div>
        </Dialog>

        <div
          class="grid min-h-0 flex-1 min-w-0 grid-rows-[auto_minmax(0,1fr)] items-stretch gap-4 lg:grid-cols-[14rem_minmax(0,1fr)] lg:grid-rows-1"
        >
          <aside
            class="!bg-transparent flex max-h-40 min-h-0 min-w-0 flex-col gap-3 overflow-y-auto lg:max-h-none lg:overflow-visible"
          >
            <section
              class="flex min-h-32 shrink-0 flex-col rounded-2xl border border-n-weak bg-n-solid-1 p-3 lg:min-h-0 lg:flex-1"
            >
              <div
                class="flex items-center justify-between gap-2 px-2 pb-3 pt-1"
              >
                <h2 class="mb-0 text-heading-3 text-n-slate-12">
                  {{ t('CRM.LEAD_CENTER_UI.TEXT_026') }}
                </h2>
                <span
                  class="bg-n-slate-3 px-2 py-0.5 text-label-small tabular-nums text-n-slate-11 rounded-full"
                  >{{ campaigns.length }}</span
                >
              </div>
              <p
                v-if="loading"
                class="mb-0 px-2 py-4 text-label-small text-n-slate-11"
              >
                {{ t('CRM.LEAD_CENTER_UI.TEXT_027') }}
              </p>
              <p
                v-else-if="!campaigns.length"
                class="mb-0 px-2 py-4 text-label-small text-n-slate-11"
              >
                {{ t('CRM.LEAD_CENTER_UI.TEXT_028') }}
              </p>
              <div class="flex min-h-0 flex-col gap-2 overflow-y-auto">
                <!-- 池子和「我领的」排在任务前面：任务是「怎么挖」，池子才是「今天跟谁」 -->
                <button
                  v-for="p in POOL_VIEWS"
                  :key="p.key"
                  type="button"
                  class="reset-base w-full rounded-xl border px-3 py-2.5 text-left transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-slate-10"
                  :aria-pressed="poolView === p.key"
                  :class="
                    poolView === p.key
                      ? 'border-n-slate-12 bg-n-slate-12 text-n-solid-1'
                      : 'border-transparent text-n-slate-12 hover:bg-n-slate-2'
                  "
                  @click="selectPool(p.key)"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="text-heading-3">{{ t(p.label) }}</span>
                    <span
                      v-if="p.key === 'mine' && holdLimit"
                      class="text-label-small"
                      :class="
                        poolView === p.key ? 'text-white/70' : 'text-n-slate-11'
                      "
                    >
                      {{ heldCount }}/{{ holdLimit }}
                    </span>
                  </div>
                </button>
                <div class="my-1 border-t border-n-weak" />
                <button
                  v-for="c in campaigns"
                  :key="c.id"
                  type="button"
                  class="reset-base w-full rounded-xl border px-3 py-3 text-left transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-slate-10"
                  :aria-pressed="Boolean(current && current.id === c.id)"
                  :class="
                    current && current.id === c.id
                      ? 'border-n-slate-12 bg-n-slate-12 text-n-solid-1'
                      : 'border-transparent text-n-slate-12 hover:bg-n-slate-2'
                  "
                  @click="selectCampaign(c)"
                >
                  <div class="break-words text-heading-3 leading-relaxed">
                    {{ c.name }}
                  </div>
                  <div
                    class="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 break-words text-label-small leading-relaxed"
                    :class="
                      current && current.id === c.id
                        ? 'text-white/70'
                        : 'text-n-slate-11'
                    "
                  >
                    <span>{{
                      t('CRM.LEAD_CENTER_UI.CREATED_BY', {
                        name:
                          c.created_by_name ||
                          t('CRM.LEAD_CENTER_UI.CREATOR_UNRECORDED'),
                      })
                    }}</span>
                    <span>{{
                      t('CRM.LEAD_CENTER_UI.OWNED_BY', {
                        name:
                          c.owner_name ||
                          t('CRM.LEAD_CENTER_UI.OWNER_UNASSIGNED'),
                      })
                    }}</span>
                  </div>
                  <div
                    class="mt-1 break-words text-label-small leading-relaxed"
                    :class="
                      current && current.id === c.id
                        ? 'text-white/70'
                        : 'text-n-slate-11'
                    "
                  >
                    {{ (c.target_markets || []).map(marketLabel).join('、') }}
                  </div>
                </button>
              </div>
            </section>
            <section
              v-if="outcomeSummary && outcomeSummary.leads"
              class="shrink-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
            >
              <div
                class="flex flex-wrap items-center justify-between gap-2 px-4 pt-3"
              >
                <h2
                  class="mb-0 flex items-center gap-2 text-heading-3 text-n-slate-12"
                >
                  <Icon
                    icon="i-lucide-chart-no-axes-combined"
                    class="size-4"
                  />{{ t('CRM.LEAD_CENTER_UI.TEXT_004') }}
                </h2>
                <button
                  type="button"
                  class="reset-base flex min-h-8 items-center gap-1 rounded-lg px-2 text-label-small text-n-slate-11 hover:bg-n-alpha-2"
                  :aria-expanded="showOutcomes"
                  @click="showOutcomes = !showOutcomes"
                >
                  {{
                    showOutcomes
                      ? t('CRM.LEAD_CENTER_UI.TEXT_005')
                      : t('CRM.LEAD_CENTER_UI.TEXT_006')
                  }}
                  <Icon
                    :icon="
                      showOutcomes
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    class="size-4"
                  />
                </button>
              </div>
              <dl class="mb-0 grid grid-cols-2 gap-x-4 gap-y-4 px-4 pb-4 pt-3">
                <div class="min-w-0">
                  <dt class="text-label-small text-n-slate-11">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_007') }}
                  </dt>
                  <dd
                    class="mb-0 ml-0 mt-1 text-heading-1 tabular-nums text-n-slate-12"
                  >
                    {{ outcomeSummary.keywords }}
                  </dd>
                </div>
                <div class="min-w-0">
                  <dt class="text-label-small text-n-slate-11">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_008') }}
                  </dt>
                  <dd
                    class="mb-0 ml-0 mt-1 text-heading-1 tabular-nums text-n-slate-12"
                  >
                    {{ outcomeSummary.leads }}
                  </dd>
                </div>
                <div class="min-w-0">
                  <dt class="text-label-small text-n-slate-11">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_009') }}
                  </dt>
                  <dd
                    class="mb-0 ml-0 mt-1 text-heading-1 tabular-nums text-n-slate-12"
                  >
                    {{ outcomeSummary.claimed }}
                  </dd>
                </div>
                <div class="min-w-0">
                  <dt class="text-label-small text-n-slate-11">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_010') }}
                  </dt>
                  <dd
                    class="mb-0 ml-0 mt-1 text-heading-1 tabular-nums text-n-slate-12"
                  >
                    {{ outcomeSummary.won }}
                  </dd>
                </div>
                <div class="col-span-2 min-w-0 border-t border-n-weak pt-3">
                  <dt class="text-label-small text-n-slate-11">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_011') }}
                  </dt>
                  <dd
                    class="mb-0 ml-0 mt-1 text-heading-1 tabular-nums text-n-slate-12"
                  >
                    {{
                      t('CRM.LEAD_CENTER_UI.CURRENCY', {
                        amount: wanRmb(outcomeSummary.deal_rmb),
                      })
                    }}
                  </dd>
                </div>
              </dl>
              <Dialog
                ref="outcomesDialog"
                :title="t('CRM.LEAD_CENTER_UI.TEXT_004')"
                width="3xl"
                overflow-y-auto
                :show-confirm-button="false"
                :show-cancel-button="false"
                @close="showOutcomes = false"
              >
                <div class="overflow-x-auto">
                  <table class="w-max min-w-full text-label whitespace-nowrap">
                    <thead class="text-label-small text-n-slate-10">
                      <tr class="border-b border-n-weak">
                        <th class="py-2 pr-6 font-normal text-left">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_012') }}
                        </th>
                        <th class="py-2 pr-6 font-normal text-right">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_013') }}
                        </th>
                        <th class="py-2 pr-6 font-normal text-right">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_073') }}
                        </th>
                        <th class="py-2 pr-6 font-normal text-right">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_014') }}
                        </th>
                        <th class="py-2 pr-6 font-normal text-right">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_010') }}
                        </th>
                        <th class="py-2 font-normal text-right">
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_011') }}
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="row in outcomes.rows"
                        :key="row.keyword"
                        class="border-b last:border-b-0 border-n-weak"
                      >
                        <td class="py-2 pr-6 max-w-80 truncate text-n-slate-12">
                          {{ row.keyword }}
                        </td>
                        <td class="py-2 pr-6 text-right text-n-slate-11">
                          {{ row.leads }}
                        </td>
                        <td class="py-2 pr-6 text-right text-n-slate-11">
                          {{
                            row.screen_rate === null
                              ? '—'
                              : `${row.screen_rate}%`
                          }}
                        </td>
                        <td
                          class="py-2 pr-6 text-right"
                          :class="
                            row.claimed ? 'text-n-slate-12' : 'text-n-slate-10'
                          "
                        >
                          {{ row.claimed || '—' }}
                        </td>
                        <td class="py-2 pr-6 text-right text-n-slate-11">
                          {{ row.won || '—' }}
                        </td>
                        <td class="py-2 font-medium text-right text-n-slate-12">
                          {{ row.deal_rmb ? wanRmb(row.deal_rmb) : '—' }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <!-- 判例是人点出来的，点错了会教错模型，所以必须看得见 -->
                <div class="pt-4 mt-4 border-t border-n-weak">
                  <h3 class="mb-2 text-heading-3 text-n-slate-12">
                    {{ t('CRM.LEAD_CENTER_UI.DIRECTIONS_TITLE') }}
                  </h3>
                  <p
                    v-if="!hasDirections"
                    class="mb-0 text-label-small text-n-slate-10"
                  >
                    {{ t('CRM.LEAD_CENTER_UI.DIRECTIONS_EMPTY') }}
                  </p>
                  <template v-else>
                    <div
                      v-if="prefer.length"
                      class="flex flex-wrap items-center gap-1.5"
                    >
                      <span class="mr-1 text-label-small text-n-slate-10">{{
                        t('CRM.LEAD_CENTER_UI.DIRECTIONS_PREFER')
                      }}</span>
                      <span
                        v-for="[name, n] in prefer"
                        :key="`p-${name}`"
                        class="px-2 py-0.5 text-label-small bg-n-teal-3 text-n-teal-11 rounded-full"
                      >
                        {{ name }}<template v-if="n > 1"> ×{{ n }}</template>
                      </span>
                    </div>
                    <div
                      v-if="avoid.length || avoidReasons.length"
                      class="flex flex-wrap items-center gap-1.5 mt-2"
                    >
                      <span class="mr-1 text-label-small text-n-slate-10">{{
                        t('CRM.LEAD_CENTER_UI.DIRECTIONS_AVOID')
                      }}</span>
                      <span
                        v-for="[name, n] in avoid"
                        :key="`a-${name}`"
                        class="px-2 py-0.5 text-label-small bg-n-ruby-3 text-n-ruby-11 rounded-full"
                      >
                        {{ name }}<template v-if="n > 1"> ×{{ n }}</template>
                      </span>
                      <span
                        v-for="[why, n] in avoidReasons"
                        :key="`w-${why}`"
                        class="px-2 py-0.5 text-label-small bg-n-slate-3 text-n-slate-11 rounded-full"
                      >
                        {{ why }} ×{{ n }}
                      </span>
                    </div>
                  </template>

                  <!-- 具体是哪几条教出来的，摊开给人核对 -->
                  <div
                    v-if="learnedClaimed.length || learnedRejected.length"
                    class="mt-3 text-label-small leading-relaxed text-n-slate-10"
                  >
                    <div v-for="e in learnedClaimed" :key="`ce-${e.name}`">
                      ✓ {{ exampleLine(e) }}
                    </div>
                    <div v-for="e in learnedRejected" :key="`re-${e.name}`">
                      ✗ {{ exampleLine(e) }}
                    </div>
                  </div>
                </div>
              </Dialog>
            </section>
          </aside>
          <section
            v-if="current"
            class="flex h-full min-h-0 min-w-0 flex-col gap-3 overflow-hidden"
          >
            <div
              class="flex shrink-0 flex-wrap items-start justify-between gap-3"
            >
              <div class="min-w-0 flex-1">
                <h2 class="mb-0 break-words text-heading-2 text-n-slate-12">
                  {{ current.name }}
                </h2>
                <div
                  class="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 break-words text-label-small text-n-slate-11"
                >
                  <span>{{
                    t('CRM.LEAD_CENTER_UI.CREATED_BY', {
                      name:
                        current.created_by_name ||
                        t('CRM.LEAD_CENTER_UI.CREATOR_UNRECORDED'),
                    })
                  }}</span>
                  <span>{{
                    t('CRM.LEAD_CENTER_UI.OWNED_BY', {
                      name:
                        current.owner_name ||
                        t('CRM.LEAD_CENTER_UI.OWNER_UNASSIGNED'),
                    })
                  }}</span>
                </div>
                <p
                  class="mb-0 mt-1 text-label-small leading-relaxed text-n-slate-11"
                >
                  {{
                    (current.target_markets || []).map(marketLabel).join('、')
                  }}
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <!-- 筛选条件和建档分组本来就要看到结果再调，不能只在建任务时设一次 -->
                <Button
                  :label="t('CRM.LEAD_CENTER_UI.EDIT_CAMPAIGN')"
                  icon="i-lucide-settings-2"
                  size="sm"
                  variant="outline"
                  color="slate"
                  class="!rounded-xl"
                  @click="openEdit(current)"
                />
                <Button
                  :label="
                    current.profiled_at
                      ? t('CRM.LEAD_CENTER_UI.TEXT_029')
                      : t('CRM.LEAD_CENTER_UI.TEXT_030')
                  "
                  icon="i-lucide-sparkles"
                  size="sm"
                  variant="outline"
                  color="slate"
                  class="!rounded-xl"
                  :is-loading="building"
                  @click="buildProfile"
                />
                <Button
                  v-if="current.profiled_at"
                  :label="searchButtonLabel"
                  icon="i-lucide-radar"
                  size="sm"
                  class="!rounded-xl !bg-[#ffca35] !text-[#202427]"
                  :is-loading="searchButtonLoading"
                  :disabled="
                    campaignSearchQuota?.allowed === false && !searchRefreshOnly
                  "
                  @click="runSearch"
                />
              </div>
            </div>
            <div
              data-search-quota
              class="shrink-0 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-label-small text-n-slate-11"
            >
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <template v-if="campaignSearchQuota">
                  <span class="font-medium text-n-slate-12">{{
                    t('CRM.SEARCH_VISIBILITY.OWNER_QUOTA', {
                      owner: campaignSearchQuota.owner_name,
                    })
                  }}</span>
                  <span>{{
                    t('CRM.SEARCH_VISIBILITY.USED', {
                      used: campaignSearchQuota.used,
                    })
                  }}</span>
                  <span
                    v-if="campaignSearchQuota.limit != null"
                    :class="campaignSearchQuota.allowed ? '' : 'text-n-ruby-11'"
                    >{{
                      t('CRM.SEARCH_VISIBILITY.REMAINING', {
                        left: campaignSearchQuota.remaining,
                        limit: campaignSearchQuota.limit,
                      })
                    }}</span
                  >
                  <span v-else>{{ t('CRM.SEARCH_VISIBILITY.UNLIMITED') }}</span>
                  <span>{{ t('CRM.SEARCH_VISIBILITY.METRIC') }}</span>
                </template>
                <span v-else>{{ t('CRM.SEARCH_VISIBILITY.NO_OWNER') }}</span>
              </div>
              <div class="mt-1">
                {{
                  t('CRM.SEARCH_VISIBILITY.SCOPE', {
                    markets: (current.target_markets || []).length,
                    keywords: (current.keywords || []).length,
                  })
                }}
              </div>
              <div
                v-if="campaignSearchState"
                data-search-run
                role="status"
                aria-live="polite"
                class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-n-weak pt-2"
              >
                <span
                  class="font-medium"
                  :class="
                    campaignSearchState === 'failed'
                      ? 'text-n-ruby-11'
                      : 'text-n-slate-12'
                  "
                  >{{ campaignSearchStateLabel }}</span
                >
                <span v-if="campaignSearchTime">{{ campaignSearchTime }}</span>
                <span v-if="searchRetryAvailable" class="w-full text-n-amber-11">
                  {{ t('CRM.SEARCH_VISIBILITY.RETRY_HINT') }}
                </span>
                <span v-else-if="searchPollPaused" class="w-full">
                  {{ t('CRM.SEARCH_VISIBILITY.POLL_PAUSED') }}
                </span>
                <span
                  v-if="
                    campaignSearchState === 'completed' &&
                    campaignSearchRun.created_leads != null
                  "
                  >{{
                    t('CRM.SEARCH_VISIBILITY.RESULT', {
                      companies: campaignSearchRun.created_companies,
                      leads: campaignSearchRun.created_leads,
                    })
                  }}</span
                >
                <span
                  v-if="campaignSearchState === 'failed'"
                  class="w-full break-words text-n-ruby-11"
                  >{{ campaignSearchRun.error || current.last_error }}</span
                >
              </div>
            </div>
            <div
              class="flex shrink-0 flex-wrap items-center gap-2 border-b border-n-weak pb-3"
            >
              <div
                class="inline-flex max-w-full items-center gap-1 overflow-x-auto rounded-xl bg-n-slate-3 p-1"
                role="group"
                :aria-label="t('CRM.LEAD_CENTER_UI.TEXT_033')"
              >
                <button
                  v-for="tab in [
                    { key: 'leads', label: t('CRM.LEAD_CENTER_UI.TEXT_034') },
                    { key: 'profile', label: t('CRM.LEAD_CENTER_UI.TEXT_035') },
                    {
                      key: 'keywords',
                      label: t('CRM.LEAD_CENTER_UI.TEXT_007'),
                    },
                  ]"
                  :key="tab.key"
                  type="button"
                  class="reset-base flex min-h-9 shrink-0 items-center gap-2 rounded-lg px-3 text-label transition-colors"
                  :class="
                    detailTab === tab.key
                      ? 'bg-[#202427] text-white shadow-sm'
                      : 'text-n-slate-11 hover:bg-n-alpha-2'
                  "
                  :aria-pressed="detailTab === tab.key"
                  @click="detailTab = tab.key"
                >
                  {{ tab.label
                  }}<span
                    v-if="tab.key === 'leads'"
                    class="rounded-md bg-black/5 px-1.5 text-label-small tabular-nums"
                    :class="detailTab === tab.key ? 'bg-white/15' : ''"
                    >{{ visibleLeads.length }}</span
                  >
                </button>
              </div>
            </div>
            <div v-show="detailTab === 'leads'" class="min-h-0 flex-1">
              <!-- 线索池：搜出来的潜在客户。邮箱默认锁着，点「解锁」才去 Apollo 换真地址（扣 credits）。 -->
              <div
                v-if="visibleLeads.length"
                class="flex h-full min-h-0 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
              >
                <div class="shrink-0 border-b border-n-weak px-5 py-3">
                  <div
                    class="flex flex-wrap items-center justify-between gap-2"
                  >
                    <h3
                      class="mb-0 flex items-center gap-2 text-heading-2 text-n-slate-12"
                    >
                      {{ t('CRM.LEAD_CENTER_UI.TEXT_034') }}
                      <span class="ml-1 text-label-small text-n-slate-11"
                        >{{ visibleLeads.length }}
                        {{ t('CRM.LEAD_CENTER_UI.TEXT_036') }}</span
                      >
                      <button
                        v-tooltip.top="{
                          content: t('CRM.LEAD_CENTER_UI.TEXT_038'),
                          triggers: ['hover', 'focus'],
                          delay: 0,
                        }"
                        type="button"
                        :aria-label="t('CRM.LEAD_CENTER_UI.TEXT_038')"
                        class="reset-base inline-flex !size-6 shrink-0 items-center justify-center rounded-full !p-0 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-slate-8"
                      >
                        <Icon
                          icon="i-lucide-circle-alert"
                          class="!size-4 shrink-0"
                        />
                      </button>
                      <!-- 「现在能不能发信」的筛子。官网邮箱不花 Apollo 额度，
                           销售口/真人邮箱那一档质量接近解锁出来的，优先发那批。 -->
                      <span
                        class="ml-2 inline-flex rounded-lg bg-n-alpha-1 p-0.5"
                      >
                        <button
                          v-for="f in MAIL_FILTERS"
                          :key="f.key"
                          type="button"
                          class="reset-base rounded-md px-2 py-1 text-label-small transition-colors"
                          :class="
                            mailFilter === f.key
                              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                              : 'text-n-slate-11 hover:text-n-slate-12'
                          "
                          @click="mailFilter = f.key"
                        >
                          {{ t(`CRM.LEAD_CENTER_UI.${f.label}`) }}
                        </button>
                      </span>
                    </h3>
                    <div
                      class="flex items-center gap-3 text-label-small text-n-slate-11"
                    >
                      <span
                        v-if="quotaLeft"
                        :class="
                          quotaLeft.left ? 'text-n-slate-11' : 'text-n-ruby-11'
                        "
                      >
                        {{
                          t('CRM.LEAD_CENTER_UI.TEXT_075', {
                            left: quotaLeft.left,
                            limit: quotaLeft.limit,
                          })
                        }}
                      </span>
                      <span>{{ t('CRM.LEAD_CENTER_UI.TEXT_037') }}</span>
                    </div>
                  </div>
                </div>
                <div
                  ref="leadList"
                  class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
                  role="region"
                  :aria-label="t('CRM.LEAD_CENTER_UI.TEXT_034')"
                  tabindex="0"
                >
                  <div
                    v-for="l in pagedLeads"
                    :key="l.id"
                    class="flex flex-col gap-3 px-5 hover:bg-n-alpha-1 xl:flex-row xl:items-start"
                    :class="
                      l.head
                        ? 'border-t border-n-weak pt-3 pb-2 first:border-t-0'
                        : 'pb-2 pl-9'
                    "
                  >
                    <div class="flex-1 min-w-0">
                      <!-- 同一家公司只在第一行显示公司信息，后面几个联系人直接接在下面 -->
                      <div
                        v-if="l.head"
                        class="flex flex-wrap items-center gap-x-2 gap-y-1.5 text-label"
                      >
                        <span
                          class="min-w-0 break-words text-heading-3 text-n-slate-12"
                          >{{ l.company_name }}</span
                        >
                        <!-- 域名点得开：这屏上要判断「这家像不像买家」，
                     点进官网看一眼比任何标签都准（AI 初筛也只是看名字和域名猜的）。 -->
                        <!-- 用 Apollo 给的完整网址，别拿主域名硬拼：
                     有些站只在 www 上存在，裸域名连 DNS 记录都没有
                     （xploretech.com 查不到 A 记录，www.xploretech.com 才是活的）。 -->
                        <!-- 官网打不开的就不给链接了，摆个说明——
                     链接点了也是「无法访问此网站」，不如直接说清楚为什么 -->
                        <span
                          v-if="l.domain && siteIssue(l)"
                          class="inline-flex min-w-0 items-center gap-1 text-label-small text-n-slate-9"
                          :title="t('CRM.LEAD_CENTER_UI.SITE_BLOCKED_HINT')"
                        >
                          <Icon
                            icon="i-lucide-unlink"
                            class="size-3 shrink-0"
                          />
                          <span class="min-w-0 break-all"
                            >{{ l.domain }} · {{ siteIssue(l).label }}</span
                          >
                        </span>
                        <a
                          v-else-if="l.domain"
                          :href="siteHref(l)"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex min-w-0 items-center gap-1 text-label-small text-n-slate-11 hover:text-n-slate-12 hover:underline"
                        >
                          <span class="min-w-0 break-all">{{ l.domain }}</span>
                          <Icon
                            icon="i-lucide-external-link"
                            class="size-3 shrink-0"
                          />
                        </a>
                        <!-- 行业来自 NAICS 官方代码（见 Crm::NaicsLabel），
                     不是 Apollo 的 industry 字段——那个字段搜索接口根本不返回 -->
                        <span
                          v-if="l.industry"
                          class="inline-flex max-w-full items-center bg-n-amber-3 px-2.5 py-0.5 text-label-small leading-5 text-n-amber-11 ring-1 ring-inset ring-n-amber-6 rounded-full"
                          >{{ l.industry }}</span
                        >
                        <!-- 国家用中文，和任务头部的「德国、美国」一个写法。
                     market 为空时退回 country 列（英文），不至于什么都不显示。 -->
                        <span
                          v-if="l.market || l.country"
                          class="text-label-small text-n-slate-10"
                          >{{ marketLabel(l.market) || l.country }}</span
                        >
                        <!-- 匹配度：列表按它排序。分越高越值得先看。
                     70 以上给亮色，中间灰，低分只在展开折叠后才看得到。 -->
                        <span
                          v-if="l.screen_score != null"
                          class="shrink-0 rounded-md px-1.5 py-0.5 text-label-small tabular-nums"
                          :class="
                            l.screen_score >= 70
                              ? 'bg-n-teal-3 text-n-teal-11'
                              : 'bg-n-slate-3 text-n-slate-11'
                          "
                        >
                          {{
                            t('CRM.LEAD_CENTER_UI.MATCH_SCORE', {
                              score: l.screen_score,
                            })
                          }}
                        </span>
                        <!-- AI 初筛：关键词是模糊匹配，会把媒体和招聘公司一起带出来。
                     只打标不自动删——AI 也会看走眼。 -->
                        <span
                          v-if="l.screen && l.screen !== 'yes'"
                          class="max-w-full px-1.5 py-0.5 text-label-small rounded-full"
                          :class="
                            l.screen === 'no'
                              ? 'bg-n-ruby-3 text-n-ruby-11'
                              : 'bg-n-slate-3 text-n-slate-11'
                          "
                          :title="l.screen_why"
                        >
                          {{
                            l.screen === 'no'
                              ? t('CRM.LEAD_CENTER_UI.TEXT_039')
                              : t('CRM.LEAD_CENTER_UI.TEXT_040')
                          }}
                          <template v-if="l.screen_why"
                            >· {{ l.screen_why }}</template
                          >
                        </span>
                        <span
                          v-if="l.dup_customer_id"
                          class="px-1.5 py-0.5 text-label-small bg-n-amber-3 text-n-amber-11 rounded-full"
                        >
                          {{ dupLabel(l) }}
                        </span>
                        <span
                          v-if="l.status === 'CLAIMED'"
                          class="px-1.5 py-0.5 text-label-small bg-n-teal-3 text-n-teal-11 rounded-full"
                        >
                          {{ t('CRM.LEAD_CENTER_UI.TEXT_009') }}
                        </span>
                      </div>
                      <div
                        class="mt-2 break-words text-label-small leading-relaxed text-n-slate-11"
                      >
                        <span
                          v-for="(part, i) in leadMeta(l)"
                          :key="i"
                          :class="part.tone"
                          >{{ i ? ' · ' : '' }}{{ part.text }}</span
                        >
                      </div>
                      <!-- 公司资料：搜索阶段白给的，不花 credits。
                     电话和领英能直接用——解锁邮箱要花钱，这两个不要。 -->
                      <div
                        v-if="l.head && orgFacts(l).length"
                        class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-label-small text-n-slate-10"
                      >
                        <template v-for="f in orgFacts(l)" :key="f.key">
                          <a
                            v-if="f.href"
                            :href="f.href"
                            :target="f.key === 'linkedin' ? '_blank' : null"
                            rel="noopener noreferrer"
                            class="inline-flex items-center gap-1 hover:text-n-slate-12 hover:underline"
                          >
                            <Icon
                              :icon="f.icon"
                              class="shrink-0"
                              :class="
                                f.key === 'linkedin' ? '!size-4' : 'size-3'
                              "
                            />
                            {{ f.text }}
                          </a>
                          <span v-else>{{ f.text }}</span>
                        </template>
                        <!-- 外部情报：接不进系统，但点一下就能看，比没有强 -->
                        <a
                          v-for="x in externalLookups(l)"
                          :key="x.key"
                          :href="x.href"
                          target="_blank"
                          rel="noopener noreferrer"
                          :title="x.hint"
                          class="inline-flex items-center gap-1 hover:text-n-slate-12 hover:underline"
                        >
                          <img
                            v-if="x.img"
                            :src="x.img"
                            alt=""
                            class="size-4 shrink-0 rounded-sm"
                          />
                          <Icon
                            v-else
                            :icon="x.icon"
                            class="!size-4 shrink-0"
                          />
                          {{ x.label }}
                        </a>
                      </div>
                      <!-- 背调结果：AI 真读了官网，比初筛那个标签硬气得多 -->
                      <div
                        v-if="l.head && l.bg"
                        class="mt-2 rounded-lg bg-n-alpha-1 px-3 py-2 text-label-small leading-relaxed text-n-slate-11"
                      >
                        <template v-if="l.bg.status === 'ok'">
                          <div
                            v-if="l.bg.note"
                            class="flex items-start gap-1.5 text-n-slate-12"
                          >
                            <Icon
                              icon="i-lucide-sparkles"
                              class="mt-0.5 size-3 shrink-0"
                            />
                            <span class="min-w-0">{{ l.bg.note }}</span>
                          </div>
                          <div v-if="l.bg.business" class="mt-1">
                            <span class="text-n-slate-9"
                              >{{ t('CRM.LEAD_CENTER_UI.BG_BUSINESS') }} ·
                            </span>
                            {{ l.bg.business }}
                          </div>
                          <div v-if="l.bg.buying" class="mt-1">
                            <span class="text-n-slate-9"
                              >{{ t('CRM.LEAD_CENTER_UI.BG_BUYING') }} ·
                            </span>
                            {{ l.bg.buying }}
                          </div>
                          <!-- 欧盟官方税号验证：三方证据里唯一官方的一方。
                       验不过也照样显示——官网印着个验不过的号，比查不到更该看见。 -->
                          <div
                            v-if="l.bg.vat"
                            class="mt-1 flex items-start gap-1.5"
                            :class="
                              l.bg.vat_status === 'valid'
                                ? 'text-n-teal-11'
                                : 'text-n-ruby-11'
                            "
                          >
                            <Icon
                              :icon="
                                l.bg.vat_status === 'valid'
                                  ? 'i-lucide-badge-check'
                                  : 'i-lucide-badge-alert'
                              "
                              class="mt-0.5 size-3 shrink-0"
                            />
                            <span class="min-w-0">
                              {{
                                t(
                                  l.bg.vat_status === 'valid'
                                    ? 'CRM.LEAD_CENTER_UI.BG_VAT_OK'
                                    : 'CRM.LEAD_CENTER_UI.BG_VAT_BAD',
                                  { no: l.bg.vat }
                                )
                              }}
                              <template v-if="l.bg.vat_name"
                                >· {{ l.bg.vat_name }}</template
                              >
                            </span>
                          </div>
                          <!-- 官网上公开的业务邮箱：不用解锁、不花 Apollo 积分就能发信。
                               点一下复制——业务员要的就是把它贴进收件人框。 -->
                          <div
                            v-if="l.bg.emails && l.bg.emails.length"
                            class="mt-2 flex min-w-0 flex-wrap items-center gap-2"
                          >
                            <span
                              class="shrink-0 text-label-small text-n-slate-10"
                            >
                              {{ t('CRM.LEAD_CENTER_UI.BG_SITE_EMAILS') }}
                            </span>
                            <button
                              v-for="m in l.bg.emails"
                              :key="m"
                              type="button"
                              class="reset-base group/email inline-flex min-h-7 min-w-0 max-w-full items-center gap-1.5 whitespace-normal rounded-sm bg-transparent px-0 py-1 text-label text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50"
                              :title="
                                t('CRM.LEAD_CENTER_UI.BG_EMAIL_COPY_TIP', {
                                  mail: m,
                                })
                              "
                              :aria-label="
                                t('CRM.LEAD_CENTER_UI.BG_EMAIL_COPY_TIP', {
                                  mail: m,
                                })
                              "
                              @click.stop="copyEmail(m)"
                            >
                              <span class="min-w-0 break-all text-left">{{
                                m
                              }}</span>
                              <Icon
                                icon="i-lucide-copy"
                                class="size-3 shrink-0 text-n-slate-10 opacity-0 transition-opacity group-hover/email:opacity-100 group-focus-visible/email:opacity-100 [@media(hover:none)]:opacity-100 motion-reduce:transition-none"
                                aria-hidden="true"
                              />
                            </button>
                          </div>
                          <div
                            class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-n-slate-9"
                          >
                            <!-- 提不到邮箱时，联系表单链接是业务员唯一的入口，比一片空白强 -->
                            <a
                              v-if="
                                l.bg.contact_url &&
                                !(l.bg.emails && l.bg.emails.length)
                              "
                              :href="l.bg.contact_url"
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-1 hover:text-n-slate-12 hover:underline"
                            >
                              {{ t('CRM.LEAD_CENTER_UI.BG_CONTACT_FORM') }}
                            </a>
                            <span v-if="l.bg.employees">
                              {{ t('CRM.LEAD_CENTER_UI.BG_SIZE') }} ·
                              {{
                                t('CRM.LEAD_CENTER_UI.BG_EMPLOYEES', {
                                  count: l.bg.employees,
                                })
                              }}
                            </span>
                            <span v-if="l.bg.legit === 'real'">
                              {{ t('CRM.LEAD_CENTER_UI.BG_LEGIT_REAL') }}
                            </span>
                            <span
                              v-else-if="l.bg.legit === 'suspicious'"
                              class="text-n-ruby-11"
                            >
                              {{ t('CRM.LEAD_CENTER_UI.BG_LEGIT_SUSPICIOUS') }}
                            </span>
                            <a
                              v-if="l.bg.url"
                              :href="l.bg.url"
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center gap-1 hover:text-n-slate-12 hover:underline"
                            >
                              {{ t('CRM.LEAD_CENTER_UI.BG_SITE') }}
                              <Icon
                                icon="i-lucide-external-link"
                                class="size-3 shrink-0"
                              />
                            </a>
                          </div>
                        </template>
                        <span v-else class="text-n-slate-9">
                          {{ t('CRM.LEAD_CENTER_UI.BG_NO_SITE') }}
                        </span>
                      </div>
                    </div>
                    <div
                      class="flex w-full shrink-0 flex-wrap items-center justify-end gap-2 xl:w-auto xl:self-start"
                    >
                      <Button
                        v-if="l.head && l.domain && l.status !== 'CLAIMED'"
                        :label="
                          bgBusyId === l.id || l.bg_running
                            ? t('CRM.LEAD_CENTER_UI.BG_RUNNING')
                            : t('CRM.LEAD_CENTER_UI.BG_ACTION')
                        "
                        icon="i-lucide-search-check"
                        size="xs"
                        class="shrink-0 !h-8 !rounded-xl"
                        variant="outline"
                        color="slate"
                        :is-loading="bgBusyId === l.id || l.bg_running"
                        @click="runBgCheck(l)"
                      />
                      <!-- 共享池：没领的先领。解锁和建档会自动领取，
                           这个按钮给「先占住、再慢慢研究」用。 -->
                      <Button
                        v-if="!l.mine && l.status !== 'CLAIMED'"
                        :label="t('CRM.LEAD_CENTER_UI.TEXT_078')"
                        size="xs"
                        class="shrink-0 !h-8 !rounded-xl"
                        :is-loading="busyLeadId === l.id"
                        @click="takeLead(l)"
                      />
                      <Button
                        v-if="l.mine && l.status !== 'CLAIMED'"
                        :label="t('CRM.LEAD_CENTER_UI.TEXT_079')"
                        size="xs"
                        class="shrink-0 !h-8 !rounded-xl"
                        variant="outline"
                        color="slate"
                        :is-loading="busyLeadId === l.id"
                        @click="releaseLead(l)"
                      />
                      <Button
                        v-if="
                          !l.email &&
                          l.email_available &&
                          l.status !== 'CLAIMED'
                        "
                        :label="t('CRM.LEAD_CENTER_UI.TEXT_044')"
                        size="xs"
                        class="shrink-0 !h-8 !rounded-xl"
                        variant="outline"
                        color="slate"
                        :is-loading="busyLeadId === l.id"
                        @click="unlockLead(l)"
                      />
                      <Button
                        v-if="l.status !== 'CLAIMED'"
                        :label="t('CRM.LEAD_CENTER_UI.TEXT_014')"
                        size="xs"
                        class="shrink-0 !h-8 !rounded-xl !bg-[#ffca35] !text-[#202427]"
                        :is-loading="busyLeadId === l.id"
                        @click="claimLead(l)"
                      />
                      <div
                        v-if="l.status !== 'CLAIMED'"
                        class="relative shrink-0"
                      >
                        <button
                          type="button"
                          class="reset-base flex size-8 items-center justify-center rounded-xl text-n-slate-11 hover:bg-n-ruby-3 hover:text-n-ruby-11"
                          :title="t('CRM.LEAD_CENTER_UI.TEXT_045')"
                          @click="
                            discardMenuFor =
                              discardMenuFor === l.id ? null : l.id
                          "
                        >
                          <Icon icon="i-lucide-x" class="size-4" />
                        </button>
                        <!-- 选原因就等于丢弃，不用再点一次确认 -->
                        <div
                          v-if="discardMenuFor === l.id"
                          class="absolute right-0 top-9 z-20 w-44 rounded-xl border border-n-weak bg-n-solid-1 py-1 shadow-lg"
                        >
                          <div
                            class="px-3 py-1.5 text-label-small text-n-slate-10"
                          >
                            {{ t('CRM.LEAD_CENTER_UI.DISCARD_TITLE') }}
                          </div>
                          <button
                            v-for="r in DISCARD_REASONS"
                            :key="r"
                            type="button"
                            class="reset-base block w-full px-3 py-1.5 text-left text-label-small text-n-slate-12 hover:bg-n-alpha-1"
                            @click="discardLead(l, r)"
                          >
                            {{ t(`CRM.LEAD_CENTER_UI.DISCARD_${r}`) }}
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
                <button
                  v-if="foldedLeads.length"
                  type="button"
                  class="reset-base shrink-0 border-t border-n-weak px-5 py-2.5 text-left text-label-small text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12"
                  @click="showNotBuyers = !showNotBuyers"
                >
                  {{
                    showNotBuyers
                      ? t('CRM.LEAD_CENTER_UI.FOLDED_HIDE', {
                          count: foldedLeads.length,
                        })
                      : t('CRM.LEAD_CENTER_UI.FOLDED_SHOW', {
                          count: foldedLeads.length,
                          kinds: foldedKinds,
                        })
                  }}
                </button>
                <PaginationFooter
                  v-model:current-page="leadPage"
                  :total-items="leadGroups.length"
                  :items-per-page="leadPageSize"
                  class="relative !h-auto min-h-14 shrink-0 flex-wrap gap-3 !bg-n-solid-1 !px-5 before:hidden"
                />
              </div>

              <div
                v-else
                class="flex h-full min-h-0 flex-col items-center justify-center gap-3 overflow-y-auto rounded-2xl border border-dashed border-n-weak bg-n-solid-1 px-6 py-10 text-center"
              >
                <div
                  class="flex size-12 items-center justify-center rounded-2xl bg-n-slate-3"
                >
                  <Icon
                    :icon="searching ? 'i-lucide-radar' : 'i-lucide-search'"
                    class="size-6 text-n-slate-11"
                  />
                </div>
                <h3 class="mb-0 text-heading-3 text-n-slate-12">
                  {{
                    searching
                      ? t('CRM.LEAD_CENTER_UI.TEXT_046')
                      : current.profiled_at
                        ? t('CRM.LEAD_CENTER_UI.TEXT_047')
                        : t('CRM.LEAD_CENTER_UI.TEXT_048')
                  }}
                </h3>
                <p
                  class="mb-0 max-w-md text-label-small leading-relaxed text-n-slate-11"
                >
                  {{
                    searching
                      ? t('CRM.LEAD_CENTER_UI.TEXT_049')
                      : current.profiled_at
                        ? t('CRM.LEAD_CENTER_UI.TEXT_050')
                        : t('CRM.LEAD_CENTER_UI.TEXT_051')
                  }}
                </p>
              </div>
            </div>
            <div
              v-show="detailTab === 'profile'"
              class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
            >
              <div class="flex flex-col gap-4">
                <!-- 喂给模型的真实数据：让人看得见画像是从哪来的 -->
                <div
                  v-if="facts.top_countries"
                  class="p-4 border rounded-2xl border-n-weak bg-n-alpha-1"
                >
                  <h3 class="mb-2 text-heading-3 text-n-slate-12">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_052') }}
                  </h3>
                  <div class="text-label-small text-n-slate-11">
                    <div>
                      {{ t('CRM.LEAD_CENTER_UI.TEXT_053')
                      }}{{ facts.deal_customer_count }}
                      {{ t('CRM.LEAD_CENTER_UI.TEXT_054') }}
                    </div>
                    <div class="mt-2 leading-relaxed">
                      {{ t('CRM.LEAD_CENTER_UI.TEXT_055') }}
                      <span
                        v-for="c in (facts.top_countries || []).slice(0, 6)"
                        :key="c.country"
                        class="mr-2"
                      >
                        {{ marketLabel(c.country) }}
                        {{ Math.round(c.deal_rmb / 10000)
                        }}{{ t('CRM.LEAD_CENTER_UI.TEXT_056') }}
                      </span>
                    </div>
                    <div class="mt-2 leading-relaxed">
                      {{ t('CRM.LEAD_CENTER_UI.TEXT_057') }}
                      <span
                        v-for="p in (facts.top_products || []).slice(0, 5)"
                        :key="p.name"
                        class="mr-2"
                      >
                        {{ p.name
                        }}<template v-if="p.avg_price">{{
                          t('CRM.LEAD_CENTER_UI.PRICE', { price: p.avg_price })
                        }}</template>
                      </span>
                    </div>
                  </div>
                </div>

                <!-- 理想客户画像 -->
                <div
                  v-if="personaRows.length"
                  class="p-4 border rounded-2xl border-n-weak"
                >
                  <h3 class="mb-3 text-heading-3 text-n-slate-12">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_058') }}
                  </h3>
                  <div
                    v-for="row in personaRows"
                    :key="row.key"
                    class="py-3 border-b last:border-b-0 border-n-weak"
                  >
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="text-label font-medium text-n-slate-12">{{
                        row.label
                      }}</span>
                      <span
                        class="px-1.5 py-0.5 text-label-small rounded-full"
                        :class="
                          row.fromData
                            ? 'bg-n-teal-3 text-n-teal-11'
                            : 'bg-n-amber-3 text-n-amber-11'
                        "
                      >
                        {{
                          row.fromData
                            ? t('CRM.LEAD_CENTER_UI.TEXT_059')
                            : t('CRM.LEAD_CENTER_UI.TEXT_060')
                        }}
                      </span>
                    </div>
                    <div class="mt-1 text-label text-n-slate-11">
                      {{ row.value }}
                    </div>
                  </div>
                  <p
                    v-if="(current.inferred_fields || []).length"
                    class="mt-3 text-label-small text-n-amber-11"
                  >
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_061') }}
                  </p>
                </div>

                <p
                  v-if="!personaRows.length && !facts.top_countries"
                  class="rounded-2xl border border-dashed border-n-weak p-8 text-center text-label-small text-n-slate-11"
                >
                  {{ t('CRM.LEAD_CENTER_UI.TEXT_062') }}
                </p>
                <p
                  v-if="current.run_model && current.profiled_at"
                  class="mb-0 text-label-small text-n-slate-11"
                >
                  {{ t('CRM.LEAD_CENTER_UI.TEXT_063') }} {{ current.run_model }}
                  {{ t('CRM.LEAD_CENTER_UI.TEXT_064') }}
                  {{ new Date(current.profiled_at).toLocaleString('zh-CN') }}
                </p>
              </div>
            </div>
            <div
              v-show="detailTab === 'keywords'"
              class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
            >
              <!-- 关键词 -->
              <div
                v-if="Object.keys(keywordsByMarket).length"
                class="p-4 border rounded-2xl border-n-weak"
              >
                <h3 class="mb-3 text-heading-3 text-n-slate-12">
                  {{ t('CRM.LEAD_CENTER_UI.TEXT_065') }}
                  <span class="text-label-small font-normal text-n-slate-10">{{
                    t('CRM.LEAD_CENTER_UI.TEXT_066')
                  }}</span>
                </h3>
                <div
                  v-for="(list, market) in keywordsByMarket"
                  :key="market"
                  class="mb-5 last:mb-0"
                >
                  <div class="mb-1.5 text-label-small text-n-slate-10">
                    {{ marketLabel(market) }}
                    <span v-if="localeNote(market, list[0] && list[0].locale)"
                      >· {{ localeNote(market, list[0].locale) }}</span
                    >
                  </div>
                  <div class="flex flex-wrap gap-1.5">
                    <span
                      v-for="(k, i) in list"
                      :key="`${market}-${i}`"
                      class="max-w-full break-words rounded-lg border px-3 py-2 text-label-small"
                      :class="gradeStyle(k.grade)"
                    >
                      {{ k.text }}
                      <span class="ml-1 text-n-slate-11">{{
                        gradeLabel(k.grade)
                      }}</span>
                    </span>
                  </div>
                </div>
                <div
                  v-if="deadKeywords.length"
                  class="mt-4 border-t border-n-weak pt-3"
                >
                  <div class="mb-1.5 text-label-small text-n-slate-10">
                    {{ t('CRM.LEAD_CENTER_UI.TEXT_071') }}
                  </div>
                  <div class="flex flex-wrap gap-1.5">
                    <span
                      v-for="word in deadKeywords"
                      :key="`dead-${word}`"
                      class="max-w-full break-words rounded-lg border border-dashed border-n-weak px-3 py-2 text-label-small text-n-slate-11 line-through"
                    >
                      {{ word }}
                    </span>
                  </div>
                </div>
              </div>

              <p
                v-if="!Object.keys(keywordsByMarket).length"
                class="rounded-2xl border border-dashed border-n-weak p-8 text-center text-label-small text-n-slate-11"
              >
                {{ t('CRM.LEAD_CENTER_UI.TEXT_067') }}
              </p>
            </div>
          </section>
          <div
            v-else
            class="flex min-h-0 flex-col items-center justify-center gap-3 overflow-y-auto rounded-2xl border border-dashed border-n-weak px-6 py-12 text-center"
          >
            <Icon icon="i-lucide-target" class="size-8 text-n-slate-10" />
            <h2 class="mb-0 text-heading-2 text-n-slate-12">
              {{
                loading
                  ? t('CRM.LEAD_CENTER_UI.TEXT_068')
                  : t('CRM.LEAD_CENTER_UI.TEXT_069')
              }}
            </h2>
            <p
              class="mb-0 max-w-sm text-label-small leading-relaxed text-n-slate-11"
            >
              {{ t('CRM.LEAD_CENTER_UI.TEXT_070') }}
            </p>
            <Button
              v-if="!loading"
              :label="t('CRM.LEAD_CENTER_UI.TEXT_003')"
              icon="i-lucide-plus"
              size="sm"
              class="!rounded-xl !bg-[#ffca35] !text-[#202427]"
              @click="openCreate"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
