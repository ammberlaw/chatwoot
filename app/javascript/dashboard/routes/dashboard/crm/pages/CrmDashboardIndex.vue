<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

import CrmAreaChart from 'dashboard/components-next/CRM/charts/CrmAreaChart.vue';
import CrmBarChart from 'dashboard/components-next/CRM/charts/CrmBarChart.vue';
import CrmDoughnutChart from 'dashboard/components-next/CRM/charts/CrmDoughnutChart.vue';
import CrmKpiCard from 'dashboard/components-next/CRM/CrmKpiCard.vue';
import CrmBlackDashboard from 'dashboard/components-next/CRM/CrmBlackDashboard.vue';
import {
  themeColor,
  usesClassicContentColors,
} from 'dashboard/components-next/CRM/charts/chartColors';
import { useThemeSignal } from 'dashboard/components-next/CRM/charts/useThemeSignal';
import { STATUS_TONE } from 'dashboard/helper/statusTone';
import MonthPicker from 'dashboard/components-next/monthpicker/MonthPicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmSentEmailRankChart from 'dashboard/components-next/CRM/CrmSentEmailRankChart.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();

const stats = ref(null);
const loading = ref(true);
const error = ref(false);

const period = ref('month'); // month | quarter | year
const selectedMonth = ref(new Date().getMonth() + 1); // 1-12
const selectedYear = ref(new Date().getFullYear());
const yearOptions = [
  new Date().getFullYear() - 2,
  new Date().getFullYear() - 1,
  new Date().getFullYear(),
];

// 季度 ↔ selectedMonth 互映（季度用当季首月定位对应桶）
const selectedQuarter = computed({
  get: () => Math.floor((selectedMonth.value - 1) / 3) + 1,
  set: q => {
    selectedMonth.value = (q - 1) * 3 + 1;
  },
});

// 月份筛选桥接到紫玻璃 MonthPicker（值 'YYYY-MM'，拆合回写年/月两个 ref）。
const pad = n => String(n).padStart(2, '0');
const monthModel = computed({
  get: () => `${selectedYear.value}-${pad(selectedMonth.value)}`,
  set: v => {
    const [y, m] = (v || '').split('-');
    if (y && m) {
      selectedYear.value = Number(y);
      selectedMonth.value = Number(m);
    }
  },
});
// 季度 / 年度用紫玻璃 SelectCard。
const quarterOptions = [1, 2, 3, 4].map(q => ({ value: q, label: `Q${q}` }));
const yearSelectOptions = yearOptions.map(y => ({ value: y, label: `${y}年` }));

// 公司看板对所有 CRM 成员开放（2026-10-29）：口径只看 URL 参数，不再按角色强制。
// 侧栏「我的数据看板」带 scope=mine，「外贸销售部数据看板」不带。
// 别人客户的公司名由后端打码（StatsController#mask_customer），不靠前端遮。
const scope = computed(() =>
  route.query.scope === 'mine' ? 'mine' : 'company'
);

const STAGE_LABELS = {
  NEEDS_CONFIRMED: '需求确认',
  SAMPLING: '样品中',
  PENDING_PAYMENT: '待付款',
  WON: '已成交',
  LOST: '输单',
};
const STAGE_COLORS = {
  NEEDS_CONFIRMED: 'iris-6',
  SAMPLING: 'iris-8',
  PENDING_PAYMENT: 'amber-9',
  WON: 'iris-10',
  LOST: 'ruby-9',
};
// 经典灰：商机阶段排成清单，图标底色套状态色规范——还没开始的灰、在走的蓝、
// 要盯着的黄、做成了的绿、没做成的红，和商机列表里那五个状态标签同一套语义，
// 色值直接取 STATUS_TONE，不另抄一份。
const STAGE_META = {
  NEEDS_CONFIRMED: { icon: 'i-lucide-clipboard-list', tone: STATUS_TONE.idle },
  SAMPLING: { icon: 'i-lucide-package', tone: STATUS_TONE.flow },
  PENDING_PAYMENT: { icon: 'i-lucide-credit-card', tone: STATUS_TONE.busy },
  WON: { icon: 'i-lucide-circle-check', tone: STATUS_TONE.done },
  LOST: { icon: 'i-lucide-circle-x', tone: STATUS_TONE.fail },
};

const SOURCE_LABELS = {
  ALIBABA: '阿里巴巴国际站',
  WEBSITE: '官网',
  EXHIBITION: '展会',
  EMAIL: '邮件开发',
  OTHER: '其他',
};
// 环形图冷色系（紫-靛-蓝，无黄，切片可区分又协调）
const SOURCE_COLOR_KEYS = [
  'iris-9',
  'iris-9',
  'blue-9',
  'iris-6',
  'iris-6',
  'blue-6',
];

// 长春花紫色系柔和渐变：跨卡紫→靛→蓝轻微流动，无绿。完整字面量供 Tailwind 收录。
const CARD_GRADIENTS = [
  'from-n-iris-3 to-n-iris-5',
  'from-n-iris-4 to-n-blue-4',
  'from-n-blue-3 to-n-iris-5',
  'from-n-iris-3 to-n-iris-6',
];

const fetchStats = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/stats`,
      {
        params: {
          scope: scope.value === 'mine' ? 'mine' : undefined,
          year: selectedYear.value,
        },
      }
    );
    stats.value = data;
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchStats);
watch([scope, selectedYear], fetchStats);

const toYuan = micros => Math.round((micros || 0) / 1_000_000);
const money = micros => `¥${toYuan(micros).toLocaleString()}`;
const moneyYuan = v => `¥${Math.round(v).toLocaleString()}`;
const scoreFmt = v => `${v}分`;

// 商机金额按商机币种显示（商机可能是美金/欧元，不能一律 ¥）。后端返回主币种。
const CURRENCY_SYMBOL = { CNY: '¥', USD: '$', EUR: '€' };
const oppCurrency = computed(
  () => stats.value?.trends?.opportunity_currency || 'CNY'
);
const moneyOpp = v =>
  `${CURRENCY_SYMBOL[oppCurrency.value] || ''}${Math.round(v).toLocaleString()}`;

// ── KPI（按 period 读桶 + 真实环比） ──
const periodStat = computed(() => {
  const ps = stats.value?.period_stats;
  if (!ps)
    return {
      amount_micros: 0,
      order_count: 0,
      deal_customers: 0,
      new_customers: 0,
    };
  if (period.value === 'year') return ps.yearly;
  if (period.value === 'quarter') {
    const q = Math.floor((selectedMonth.value - 1) / 3);
    return ps.quarterly[q] || ps.quarterly[0];
  }
  return ps.monthly[selectedMonth.value - 1] || ps.monthly[0];
});

const periodLabel = computed(() => {
  const y = stats.value?.year || new Date().getFullYear();
  if (period.value === 'year') return `${y}年`;
  if (period.value === 'quarter') {
    return `${y}年 Q${Math.floor((selectedMonth.value - 1) / 3) + 1}`;
  }
  return `${y}年${selectedMonth.value}月`;
});

// 上一期（环比的分母）。年度没有去年的桶，返回 null，卡上就不显示环比。
const prevStat = computed(() => {
  const ps = stats.value?.period_stats;
  if (!ps) return null;
  if (period.value === 'year') return null;
  if (period.value === 'quarter') {
    const q = Math.floor((selectedMonth.value - 1) / 3);
    return q > 0 ? ps.quarterly[q - 1] : null;
  }
  return selectedMonth.value > 1 ? ps.monthly[selectedMonth.value - 2] : null;
});

// 卡片标题跟着周期走。用「月度/季度/年度」而不是「本月」——月份可以翻到过去，
// 选了 3 月还顶着「本月」两个字就是错的，具体哪一期看副标题。
const PERIOD_NOUN = { month: '月度', quarter: '季度', year: '年度' };
const periodNoun = computed(() => PERIOD_NOUN[period.value] || '月度');

const PREV_LABEL = { month: '较上月', quarter: '较上季', year: '' };
const FLAT_LABEL = { month: '上月也是', quarter: '上季也是', year: '' };

// 环比那行要和走势图挤在一张 273px 宽的卡里，完整金额会被截断成「¥3,34…」。
// 大数仍然写全，只有「较上月」后面跟的参照值缩写成万/亿。
const compactMoney = micros => {
  const yuan = Math.round((micros || 0) / 1_000_000);
  const abs = Math.abs(yuan);
  if (abs >= 100000000) return `¥${(yuan / 100000000).toFixed(2)}亿`;
  if (abs >= 10000) return `¥${(yuan / 10000).toFixed(1)}万`;
  return `¥${yuan.toLocaleString()}`;
};

// 环比：金额按百分比，个数按「差几个」——15 笔变 16 笔说「+6.7%」没人看得懂。
const makeDelta = (key, { money: isMoney = false, fmt = v => v } = {}) => {
  const prev = prevStat.value;
  if (!prev) return null;
  const now = Number(periodStat.value?.[key] || 0);
  const was = Number(prev[key] || 0);
  const label = PREV_LABEL[period.value] || '较上期';
  if (now === was) {
    const flat = FLAT_LABEL[period.value] || '上期也是';
    return { text: '持平', dir: 'flat', vs: `${flat} ${fmt(was)}` };
  }
  const dir = now > was ? 'up' : 'down';
  const sign = now > was ? '+' : '−';
  const diff = Math.abs(now - was);
  let text = `${sign}${diff}`;
  if (isMoney) {
    // 上期是 0 时算不出百分比，直接报差额
    text =
      was === 0
        ? `${sign}${fmt(diff)}`
        : `${sign}${((diff / was) * 100).toFixed(1)}%`;
  }
  return { text, dir, vs: `${label} ${fmt(was)}` };
};

// 走势取本年各月，截到所选月份为止——把还没发生的月份画成 0 会看着像断崖。
const monthlySeries = key => {
  const rows = stats.value?.period_stats?.monthly || [];
  const end = period.value === 'year' ? rows.length : selectedMonth.value;
  return rows.slice(0, end).map(r => Number(r?.[key] || 0));
};

// 成交客户里有多少是新客——「构成」类的数，画走势没意义，所以第三张卡右边放分档而不是柱子。
// 原来第二行是「占客户总数」(成交客户 / 全部客户)，但客户盘子上万、一个月成交几家到几十家，
// 这个比值永远四舍五入成 0%（生产 12719 个客户，成交 4 家 = 0.03%），等于一行废数。
// 换成「新客占比」= 新客 / 成交客户：和上一行直接对得上，也是看新客开发成效时真正要的那个数。
const customerSplit = computed(() => {
  const s = periodStat.value;
  const deals = Number(s.deal_customers) || 0;
  const share = deals ? Math.round((Number(s.new_customers) / deals) * 100) : 0;
  return [
    { label: '其中新客', value: s.new_customers, tone: 'mute' },
    { label: '新客占比', value: `${share}%`, tone: 'ink' },
  ];
});

const GMV_KPI = computed(() => ({
  label: 'GMV',
  value: money(periodStat.value.amount_micros),
  icon: 'i-lucide-banknote',
  delta: makeDelta('amount_micros', { money: true, fmt: compactMoney }),
  viz: { type: 'line', series: monthlySeries('amount_micros') },
}));

const ORDER_KPI = computed(() => ({
  label: '成交订单',
  value: periodStat.value.order_count,
  unit: '笔',
  icon: 'i-lucide-shopping-bag',
  delta: makeDelta('order_count', { fmt: v => `${v} 笔` }),
  viz: { type: 'bars', series: monthlySeries('order_count') },
}));

// 外贸销售部看板（全公司）三张卡；个人数据看板四张，新成交客户数单独占一张——
// 个人视角下「我这个月开了几个新客」本身就是要盯的数，塞进分档里看不见。
const classicKpis = computed(() => {
  const s = periodStat.value;
  if (scope.value !== 'mine') {
    return [
      GMV_KPI.value,
      ORDER_KPI.value,
      {
        label: '成交客户数',
        value: s.deal_customers,
        unit: '家',
        icon: 'i-lucide-users',
        delta: makeDelta('deal_customers', { fmt: v => `${v} 家` }),
        viz: { type: 'split', rows: customerSplit.value },
      },
    ];
  }
  return [
    GMV_KPI.value,
    ORDER_KPI.value,
    {
      label: '成交客户数',
      value: s.deal_customers,
      unit: '家',
      icon: 'i-lucide-building-2',
      delta: makeDelta('deal_customers', { fmt: v => `${v} 家` }),
      viz: { type: 'bars', series: monthlySeries('deal_customers') },
    },
    {
      label: '新成交客户数',
      value: s.new_customers,
      unit: '家',
      icon: 'i-lucide-user-plus',
      delta: makeDelta('new_customers', { fmt: v => `${v} 家` }),
      viz: { type: 'bars', series: monthlySeries('new_customers') },
    },
  ];
});

const salesKpis = computed(() => {
  const s = periodStat.value;
  return [
    {
      label: 'GMV',
      value: money(s.amount_micros),
      sub: periodLabel.value,
      icon: 'i-lucide-banknote',
    },
    {
      label: '成交订单数',
      value: s.order_count,
      sub: '笔',
      icon: 'i-lucide-shopping-bag',
    },
    {
      label: '成交客户数',
      value: s.deal_customers,
      sub: '家',
      icon: 'i-lucide-building-2',
    },
    {
      label: '新成交客户数',
      value: s.new_customers,
      sub: '家',
      icon: 'i-lucide-user-plus',
    },
  ];
});

// themeSignal：body class（主题）变化时自增。图表色板 chartPalette()/themeColor()
// 读 DOM 非响应式，切主题不会自动重算；下面产色的 computed 依赖它即可跟随切换。
const themeSignal = useThemeSignal();

// 经典灰下顶部换成带环比和走势的 KPI 卡；其余主题保持原来的渐变卡不动。
// themeSignal 让它在切主题时重算（body class 不是响应式数据）。
const isClassicKpi = computed(() => {
  void themeSignal.value;
  return usesClassicContentColors();
});
const isClassicBlack = computed(() => {
  void themeSignal.value;
  return document.body.classList.contains('theme-classic');
});

// 个人看板（scope=mine）：按业务员排的那两张榜只会剩自己一行，不渲染。
const isMine = computed(() => scope.value === 'mine');

// 成交排行腾出来的那 2/3，个人视角换成几张当下状态的小卡。
// 这几个数都是「此刻是多少」，不跟着上方的月份筛选走。
const mineMiniCards = computed(() => {
  const tt = stats.value?.totals || {};
  return [
    { label: '私海客户数', value: tt.private_customers || 0, unit: '家' },
  ];
});

// 资料完善度本来就是「满分 100 里拿了多少」，环形比一个光秃秃的数字直观。
// 进度段用黄（经典灰的主色），剩余段用 slate-4 当轨道。
const completenessRing = computed(() => {
  void themeSignal.value;
  const score = stats.value?.totals?.private_completeness;
  if (score == null) return null;
  const done = Math.max(0, Math.min(100, Math.round(score)));
  return {
    score,
    data: [done, 100 - done],
    colors: ['#ffc53d', themeColor('slate-4')],
  };
});

const kpiGridClass = computed(() =>
  isClassicKpi.value && classicKpis.value.length === 3
    ? 'grid-cols-1 sm:grid-cols-3'
    : 'grid-cols-2 xl:grid-cols-4'
);

// ── 目标完成率（半圆仪表） ──
const targetProgress = computed(() => {
  const tg = stats.value?.target;
  if (!tg) return null;
  // 分母跟着所选周期走；分子直接取同一周期的成交额，不再固定看本月
  const q = Math.floor((selectedMonth.value - 1) / 3);
  const byPeriod = {
    year: tg.yearly,
    quarter: tg.quarterly?.[q],
    month: tg.monthly?.[selectedMonth.value - 1],
  };
  const targetMicros = byPeriod[period.value] || 0;
  const done = periodStat.value.amount_micros || 0;
  if (!targetMicros) return null;
  return {
    target: money(targetMicros),
    done: money(done),
    pct: Math.min(100, Math.round((done / targetMicros) * 100)),
    remaining: money(Math.max(0, targetMicros - done)),
  };
});

// ── 月度成交额趋势（面积图） ──
const trendChart = computed(() => {
  const arr = stats.value?.trends?.monthly_amount_micros || [];
  const current = new Date().getMonth() + 1;
  return {
    labels: arr.map((_, i) => `${i + 1}月`),
    data: arr.map(toYuan),
    activeIndex: current - 1,
    empty: !arr.some(v => v),
  };
});

// ── 商机阶段（柱状图，与其它图表统一 Chart.js 风格） ──
const stageChart = computed(() => {
  void themeSignal.value;
  const byStage = stats.value?.trends?.opportunity_amount_by_stage || {};
  const rows = Object.keys(STAGE_LABELS)
    .map(stage => ({ stage, micros: byStage[stage] || 0 }))
    .filter(r => r.micros);
  return {
    stages: rows.map(r => r.stage),
    labels: rows.map(r => STAGE_LABELS[r.stage]),
    data: rows.map(r => toYuan(r.micros)),
    colors: rows.map(r => themeColor(STAGE_COLORS[r.stage])),
    empty: !rows.length,
  };
});

// 转化率：已成交金额 / 全部商机金额
const winRate = computed(() => {
  const byStage = stats.value?.trends?.opportunity_amount_by_stage || {};
  const total = Object.values(byStage).reduce((a, b) => a + (b || 0), 0);
  if (!total) return null;
  return Math.round(((byStage.WON || 0) / total) * 100);
});

// ── 客户来源占比（环形） ──
const sourceDonut = computed(() => {
  void themeSignal.value;
  const breakdown = stats.value?.source_breakdown || {};
  const rows = Object.entries(breakdown)
    .filter(([k, v]) => v && k !== 'REFERRAL')
    .sort((a, b) => b[1] - a[1]);
  return {
    labels: rows.map(([k]) => SOURCE_LABELS[k] || k),
    data: rows.map(([, v]) => v),
    colors: rows.map((_, i) =>
      themeColor(SOURCE_COLOR_KEYS[i % SOURCE_COLOR_KEYS.length])
    ),
    total: rows.reduce((a, [, v]) => a + v, 0),
    empty: !rows.length,
  };
});

// ── 业务员成交排行（横向柱，跟随所选期间，按下单日期）──
const periodMonths = computed(() => {
  if (period.value === 'year') return Array.from({ length: 12 }, (_, i) => i);
  if (period.value === 'quarter') {
    const q = Math.floor((selectedMonth.value - 1) / 3);
    return [q * 3, q * 3 + 1, q * 3 + 2];
  }
  return [selectedMonth.value - 1];
});
const ownerRank = computed(() => {
  const by = stats.value?.team?.by_owner_monthly || {};
  const months = periodMonths.value;
  const rows = Object.entries(by)
    .map(([name, arr]) => [name, months.reduce((s, i) => s + (arr[i] || 0), 0)])
    .filter(([, v]) => v)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 50);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => toYuan(v)),
    empty: !rows.length,
  };
});

// 排行图高度随人数增长（每人 34px，不足一屏则铺满 h-72=288px），
// 外层容器 overflow-y-auto 才能滚——图表分支不像经典灰那样自带列表滚动。
const RANK_ROW_PX = 34;
const RANK_MIN_PX = 288;
const rankChartHeight = computed(
  () =>
    `${Math.max(RANK_MIN_PX, ownerRank.value.labels.length * RANK_ROW_PX)}px`
);

// ── 客户成交排行（Top Customers）：按所选期间汇总「客户 × 月」的成交额与单数 ──
// 和业务员排行同一套数据组织方式，切月/季/年不用重新请求。
const topCustomers = computed(() => {
  const rows = stats.value?.team?.top_customers || [];
  const months = periodMonths.value;
  const sum = (arr, idx) => idx.reduce((acc, i) => acc + (arr?.[i] || 0), 0);
  return rows
    .map(c => ({
      id: c.id,
      name: c.name,
      masked: !!c.masked,
      amount: sum(c.amount, months),
      orders: sum(c.orders, months),
    }))
    .filter(c => c.amount > 0)
    .sort((a, b) => b.amount - a.amount)
    .slice(0, 5)
    // 别人的客户后端已经把名字和 id 抹掉了（见 StatsController#mask_customer），
    // 这里只负责给个占位名，并且不给点。
    .map((c, i) => (c.masked ? { ...c, name: `客户 ${String(i + 1).padStart(2, '0')}` } : c));
});
const countryRank = computed(() => {
  const groups = new Map();
  (stats.value?.team?.top_customers || []).forEach(customer => {
    const amount = periodMonths.value.reduce(
      (total, month) => total + (customer.amount?.[month] || 0),
      0
    );
    if (amount <= 0) return;
    const country = customer.country || '';
    const row = groups.get(country) || { country, amount: 0, customers: 0 };
    row.amount += toYuan(amount);
    row.customers += 1;
    groups.set(country, row);
  });
  return [...groups.values()].sort((a, b) => b.amount - a.amount);
});
const goCustomer = id => {
  // 打码行没有 id，点不进去。
  if (!id) return;

  router.push({
    name: 'crm_customer_detail_index',
    params: { accountId: accountId.value, id },
  });
};

// ── 业务员发信排行（跟成交排行同一套：按所选期间汇总「业务员 × 月」的发信数）──
// 发信量是过程指标，和成交额并排看才知道「发得多但没成交」还是「没发也没成交」。
const ownerEmailRank = computed(() => {
  const by = stats.value?.team?.by_owner_sent_emails || {};
  const months = periodMonths.value;
  const rows = Object.entries(by)
    .map(([name, arr]) => [
      name,
      months.reduce((sum, i) => sum + (arr[i] || 0), 0),
    ])
    .filter(([, v]) => v)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 50);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => v),
    empty: !rows.length,
  };
});
// 姓名缩写：有空格的取各段首字母（Leo Fang → LF），没空格的中文取前两字、英文取前两个字母。
const rankInitials = name => {
  const parts = String(name || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (parts.length > 1) {
    return parts
      .slice(0, 2)
      .map(w => w[0])
      .join('')
      .toUpperCase();
  }
  const one = parts[0] || '?';
  return /[\u4e00-\u9fa5]/.test(one)
    ? one.slice(0, 2)
    : one.slice(0, 2).toUpperCase();
};

// 图表组件要的 [{ name, count }]（已按多到少排好）。
const ownerEmailRankRows = computed(() =>
  ownerEmailRank.value.labels.map((name, i) => ({
    name,
    count: ownerEmailRank.value.data[i],
  }))
);

// ── 业务员资料完善度（越高越好，降序排） ──
const ownerCompleteness = computed(() => {
  const by = stats.value?.team?.by_owner_completeness || {};
  const rows = Object.entries(by)
    .filter(([, v]) => v != null)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8);
  return {
    labels: rows.map(([k]) => k),
    data: rows.map(([, v]) => v),
    empty: !rows.length,
  };
});

// ── 经典灰专属：图表改 HTML 排版（黄黑灰）。响应式跟随主题切换（无需刷新）。──
// isClassic 依赖 themeSignal 重算，图表用它做 :key 重绘。
const isClassic = computed(() => {
  void themeSignal.value;
  return usesClassicContentColors();
});
const RANK_PALETTE = ['#ffc53d', '#2a2e37', '#6b6f78', '#b9bcc4'];
const isLightBar = c => c === '#ffc53d' || c === '#b9bcc4';

// 商机阶段：图标 + 阶段名 + 金额的清单。
// 不画条子——条子要么比长短、要么配底槽说完成率，这五个阶段两样都不是。
const classicStageRows = computed(() =>
  stageChart.value.stages.map((stage, i) => ({
    label: stageChart.value.labels[i],
    amount: moneyOpp(stageChart.value.data[i]),
    pct:
      (stageChart.value.data[i] / Math.max(...stageChart.value.data, 1)) * 100,
    won: stage === 'WON',
    ...STAGE_META[stage],
  }))
);

// 排行/回复/完善度：奖牌序号 + 头像 + 进度条 行
const buildRankRows = (chart, { inverse = false, fmt }) => {
  const { labels, data } = chart;
  if (!labels.length) return [];
  const max = Math.max(...data, 1);
  const min = Math.min(...data);
  return labels.map((name, i) => {
    let pct = Math.max((data[i] / max) * 100, 6);
    if (inverse) {
      pct = max === min ? 100 : ((max - data[i]) / (max - min)) * 76 + 24;
    }
    // 名次徽章按名次换色（金/黑/灰/浅灰），这是它该表达的东西。
    // 进度条不跟着换——长度已经把数值说完了，颜色再表达一遍名次，
    // 碰上并列（七个人都 100 分）就会看成「分数不一样」。
    const color = RANK_PALETTE[Math.min(i, RANK_PALETTE.length - 1)];
    return {
      name,
      initial: (name || '?').slice(0, 1),
      value: fmt(data[i]),
      amount: data[i],
      pct,
      color,
      barColor: RANK_PALETTE[0],
      dark: isLightBar(color),
    };
  });
};
const classicRank = computed(() =>
  buildRankRows(ownerRank.value, { fmt: moneyYuan })
);
const classicCompleteness = computed(() =>
  buildRankRows(ownerCompleteness.value, { fmt: scoreFmt })
);

const PERIODS = [
  { k: 'month', l: '月度' },
  { k: 'quarter', l: '季度' },
  { k: 'year', l: '年度' },
];
</script>

<template>
  <div
    data-black-dashboard
    :data-dashboard-scope="scope"
    class="flex flex-col w-full h-full gap-4 p-4 sm:p-6 overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5 [.theme-classic_&]:sm:!p-8"
  >
    <!-- 顶栏 -->
    <div
      data-dashboard-header
      class="flex flex-wrap items-center justify-between gap-3 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center"
    >
      <div class="min-w-0">
        <h1 class="text-2xl font-semibold tracking-tight text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">
          {{
            scope === 'mine'
              ? t('CRM.DASHBOARD.HEADER_MINE')
              : t('CRM.DASHBOARD.HEADER_COMPANY')
          }}
        </h1>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <!-- 月度/季度/年度：走全站页面级 Tab 的统一标记（data-tabbar + aria-selected），
             样式在 _next-colors.scss。原来是自己写的「灰槽 + 白条」，跟别处的
             「灰槽 + 深色块」对不上——同一个人一天要认两种「现在选中哪个」。
             这里不要再写底色/阴影，写了会跟统一规则打架。 -->
        <div
          data-tabbar="page"
          class="my-0"
          :class="
            isClassicBlack
              ? '!my-0 !h-9 [&>button]:!h-full [&>button]:!py-0'
              : ''
          "
        >
          <button
            v-for="p in PERIODS"
            :key="p.k"
            :aria-selected="period === p.k"
            @click="period = p.k"
          >
            {{ p.l }}
          </button>
        </div>
        <MonthPicker
          v-if="period === 'month'"
          v-model="monthModel"
          align="right"
          trigger-class="w-36 h-9"
          :clearable="false"
        />
        <SelectCard
          v-else-if="period === 'quarter'"
          v-model="selectedQuarter"
          :options="quarterOptions"
          align="right"
          trigger-class="w-24"
        />
        <SelectCard
          v-else
          v-model="selectedYear"
          :options="yearSelectOptions"
          align="right"
          trigger-class="w-24"
        />
      </div>
    </div>

    <div v-if="loading" class="p-8 text-center text-n-slate-11">
      {{ t('CRM.DASHBOARD.LOADING') }}
    </div>

    <div
      v-else-if="error"
      role="alert"
      class="flex flex-col items-center gap-3 p-10 text-center border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
    >
      <span class="i-lucide-cloud-off size-8 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">数据加载失败，请检查网络后重试。</p>
      <button
        class="h-9 px-4 text-sm font-medium transition-colors rounded-lg bg-n-iris-9 text-n-slate-12 motion-reduce:transition-none hover:bg-n-iris-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-iris-9"
        @click="fetchStats"
      >
        重新加载
      </button>
    </div>

    <CrmBlackDashboard
      v-else-if="isClassicBlack"
      :is-mine="isMine"
      :period-label="periodLabel"
      :period-noun="periodNoun"
      :gmv="GMV_KPI"
      :summary="salesKpis.slice(1)"
      :target="targetProgress"
      :trend="trendChart"
      :rank="classicRank"
      :customers="topCustomers"
      :country-rank="countryRank"
      :stages="classicStageRows"
      :sources="sourceDonut"
      :completeness="classicCompleteness"
      :private-customers="stats?.totals?.private_customers || 0"
      :private-completeness="completenessRing?.score"
      :email-rows="ownerEmailRankRows"
      :win-rate="winRate"
      :money-format="moneyYuan"
      :initials="rankInitials"
      @customer="goCustomer"
    />
    <template v-else>
      <!-- ═══ 第 1 行：KPI ═══ -->
      <!-- 手机上排 2 列（原来单列一屏只看得到 2 张卡），并收紧内边距/字号 -->
      <div
        data-dashboard-kpis
        class="grid gap-3 sm:gap-4"
        :class="kpiGridClass"
      >
        <!-- 经典灰：带环比和走势的卡（见 CrmKpiCard） -->
        <template v-if="isClassicKpi">
          <CrmKpiCard
            v-for="kpi in classicKpis"
            :key="`c-${kpi.label}`"
            :label="kpi.label"
            :value="kpi.value"
            :unit="kpi.unit"
            :icon="kpi.icon"
            :delta="kpi.delta"
            :viz="kpi.viz"
          />
        </template>
        <!-- 其余主题：MedFlow 式暖色浅渐变卡（深字 + 真实涨跌角标） -->
        <template v-else>
          <div
            v-for="(kpi, i) in salesKpis"
            :key="kpi.label"
            class="flex flex-col justify-between p-4 sm:p-5 shadow-sm rounded-2xl bg-gradient-to-br min-h-[7rem] sm:min-h-[8.5rem]"
            :class="CARD_GRADIENTS[i]"
          >
            <div
              class="flex items-center justify-center rounded-lg size-8 sm:size-9 bg-n-solid-1/70 text-n-iris-11"
            >
              <span class="size-4 sm:size-5" :class="[kpi.icon]" />
            </div>
            <div class="min-w-0">
              <div
                class="mt-3 sm:mt-4 text-sm font-medium truncate text-n-slate-11"
              >
                {{ kpi.label }}
              </div>
              <div
                class="mt-1 text-xl sm:text-2xl font-bold truncate text-n-slate-12"
              >
                {{ kpi.value }}
              </div>
              <div class="mt-1 text-xs truncate text-n-slate-10">
                {{ kpi.sub }}
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- 全公司：排行(3) / 趋势(2)+目标(1) / 商机(2)+来源(1) / 完善度(3)
           个人：  三个数(1×3) / 趋势(2)+目标(1) / 商机(2)+来源(1)
           两边都正好铺满三列，所以共用一个栅格，不另起行。 -->
      <!-- ═══ 左栏大图 + 右栏明细 ═══ -->
      <div data-dashboard-body class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <div
          data-dashboard-column="main"
          class="flex flex-col gap-4 lg:col-span-2 min-w-0"
        >
          <div
            v-if="!isMine"
            data-dashboard-card="rank"
            class="p-5 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <h2 class="mb-4 text-base font-medium text-n-slate-12">
              业务员成交排行
            </h2>
            <div class="h-72 min-w-0">
              <div
                v-if="ownerRank.empty"
                class="flex items-center justify-center h-full text-sm text-n-slate-10"
              >
                暂无成交数据
              </div>
              <div
                v-else-if="isClassic"
                class="flex flex-col h-full gap-3 overflow-y-auto pr-1"
              >
                <div
                  v-for="(row, i) in classicRank"
                  :key="row.name"
                  class="flex items-center gap-2.5"
                >
                  <div
                    class="grid text-[11px] font-bold rounded size-5 place-items-center shrink-0"
                    :style="{
                      backgroundColor: row.color,
                      color: row.dark ? '#26340a' : '#fff',
                    }"
                  >
                    {{ i + 1 }}
                  </div>
                  <div
                    class="grid rounded-lg size-7 place-items-center bg-n-slate-3 text-[11px] font-bold text-n-slate-11 shrink-0"
                  >
                    {{ row.initial }}
                  </div>
                  <div class="flex-1 min-w-0">
                    <div
                      class="text-[13px] font-medium truncate text-n-slate-12"
                    >
                      {{ row.name }}
                    </div>
                    <div
                      class="h-1.5 mt-1 overflow-hidden rounded-full bg-n-slate-3"
                    >
                      <div
                        class="h-full rounded-full"
                        :style="{
                          width: row.pct + '%',
                          backgroundColor: row.barColor,
                        }"
                      />
                    </div>
                  </div>
                  <div class="text-[13px] font-bold text-n-slate-12 shrink-0">
                    {{ row.value }}
                  </div>
                </div>
              </div>
              <div v-else class="h-full overflow-y-auto pr-1">
                <div :style="{ height: rankChartHeight }">
                  <CrmBarChart
                    :key="themeSignal"
                    :labels="ownerRank.labels"
                    :data="ownerRank.data"
                    horizontal
                    show-values
                    :value-format="moneyYuan"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- 业务员发信排行：和成交排行同一期间口径，只认真正发成功的邮件。
               图表与团队看板共用同一个组件（CrmSentEmailRankChart）。 -->
          <CrmSentEmailRankChart
            data-dashboard-card="emails"
            v-if="!isMine"
            :rows="ownerEmailRankRows"
            :period-label="periodLabel"
          />

          <div
            data-dashboard-card="trend"
            class="p-5 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <h2 class="mb-4 text-base font-medium text-n-slate-12">
              订单金额趋势
            </h2>
            <div class="h-40 min-w-0">
              <CrmAreaChart
                v-if="!trendChart.empty"
                :key="themeSignal"
                :labels="trendChart.labels"
                :data="trendChart.data"
                :active-index="trendChart.activeIndex"
                :value-format="moneyYuan"
              />
              <div
                v-else
                class="flex items-center justify-center h-full text-sm text-n-slate-10"
              >
                暂无趋势数据
              </div>
            </div>
          </div>
          <!-- 商机阶段分布只有五行，占满主栏太空；跟完善度榜并排各半。
               个人视角没有完善度榜，它就独占一行。 -->
          <div
            data-dashboard-card="stages"
            class="grid gap-4"
            :class="isMine ? 'grid-cols-1' : 'lg:grid-cols-2'"
          >
            <div
              class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
            >
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-base font-medium text-n-slate-12">
                  商机阶段分布
                </h2>
                <span v-if="winRate != null" class="text-xs text-n-slate-11">
                  成交转化率
                  <span class="font-semibold text-n-iris-11"
                    >{{ winRate }}%</span
                  >
                </span>
              </div>
              <div class="h-72 min-w-0">
                <div
                  v-if="stageChart.empty"
                  class="flex items-center justify-center h-full text-sm text-n-slate-10"
                >
                  暂无商机数据
                </div>
                <div
                  v-else-if="isClassic"
                  class="flex flex-col justify-center h-full gap-1"
                >
                  <div
                    v-for="row in classicStageRows"
                    :key="row.label"
                    class="flex items-center gap-3 p-2 rounded-lg hover:bg-n-alpha-1"
                  >
                    <div
                      class="flex items-center justify-center rounded-lg size-9 shrink-0"
                      :class="row.tone"
                    >
                      <span class="size-5" :class="row.icon" />
                    </div>
                    <span class="text-sm text-n-slate-11">{{ row.label }}</span>
                    <span class="ml-auto text-base font-bold text-n-slate-12">
                      {{ row.amount }}
                    </span>
                  </div>
                </div>
                <CrmBarChart
                  v-else
                  :key="themeSignal"
                  :labels="stageChart.labels"
                  :data="stageChart.data"
                  :colors="stageChart.colors"
                  show-values
                  :value-format="moneyOpp"
                />
              </div>
            </div>
            <div
              v-if="!isMine"
              class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
            >
              <h2 class="mb-4 text-base font-medium text-n-slate-12">
                业务员资料完善度
              </h2>
              <div class="h-72 min-w-0">
                <div
                  v-if="ownerCompleteness.empty"
                  class="flex items-center justify-center h-full text-sm text-n-slate-10"
                >
                  暂无完善度数据
                </div>
                <div
                  v-else-if="isClassic"
                  class="flex flex-col h-full gap-3 overflow-y-auto pr-1"
                >
                  <div
                    v-for="(row, i) in classicCompleteness"
                    :key="row.name"
                    class="flex items-center gap-2.5"
                  >
                    <div
                      class="grid text-[11px] font-bold rounded size-5 place-items-center shrink-0"
                      :style="{
                        backgroundColor: row.color,
                        color: row.dark ? '#26340a' : '#fff',
                      }"
                    >
                      {{ i + 1 }}
                    </div>
                    <div
                      class="grid rounded-lg size-7 place-items-center bg-n-slate-3 text-[11px] font-bold text-n-slate-11 shrink-0"
                    >
                      {{ row.initial }}
                    </div>
                    <div class="flex-1 min-w-0">
                      <div
                        class="text-[13px] font-medium truncate text-n-slate-12"
                      >
                        {{ row.name }}
                      </div>
                      <div
                        class="h-1.5 mt-1 overflow-hidden rounded-full bg-n-slate-3"
                      >
                        <div
                          class="h-full rounded-full"
                          :style="{
                            width: row.pct + '%',
                            backgroundColor: row.barColor,
                          }"
                        />
                      </div>
                    </div>
                    <div class="text-[13px] font-bold text-n-slate-12 shrink-0">
                      {{ row.value }}
                    </div>
                  </div>
                </div>
                <CrmBarChart
                  v-else
                  :key="themeSignal"
                  :labels="ownerCompleteness.labels"
                  :data="ownerCompleteness.data"
                  horizontal
                  show-values
                  :value-format="scoreFmt"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- 右栏：按周期的明细。小卡两个一排 -->
        <div
          data-dashboard-column="details"
          class="flex flex-col gap-4 min-w-0"
        >
          <div v-if="!isMine" data-dashboard-details-title>
            <h2 class="text-base font-medium text-n-slate-12">
              {{ periodNoun }}明细
            </h2>
            <p class="mt-1 text-xs text-n-slate-10">{{ periodLabel }}</p>
          </div>
          <div v-if="isMine" class="grid grid-cols-3 gap-3">
            <div
              v-for="c in mineMiniCards"
              :key="c.label"
              class="flex flex-col justify-center p-4 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
            >
              <div class="text-sm truncate text-n-slate-11">{{ c.label }}</div>
              <div class="mt-2 text-2xl font-bold tabular-nums text-n-slate-12">
                {{ c.value }}
                <span
                  v-if="c.unit"
                  class="ml-0.5 text-sm font-medium text-n-slate-10"
                >
                  {{ c.unit }}
                </span>
              </div>
              <div v-if="c.hint" class="mt-1 text-xs text-n-slate-10">
                {{ c.hint }}
              </div>
            </div>
            <!-- 完善度：满分 100 的占比，环形比一个数字直观。窄栏里占两格 -->
            <div
              v-if="completenessRing"
              class="col-span-2 p-4 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
            >
              <div class="text-sm truncate text-n-slate-11">
                私海客户资料完善度
              </div>
              <div class="relative h-24 mx-auto mt-2 max-w-[6rem]">
                <CrmDoughnutChart
                  :key="themeSignal"
                  :data="completenessRing.data"
                  :colors="completenessRing.colors"
                  cutout="76%"
                >
                  <template #center>
                    <div class="text-xl font-bold text-n-slate-12">
                      {{ completenessRing.score }}
                    </div>
                    <div class="text-[10px] text-n-slate-10">满分 100</div>
                  </template>
                </CrmDoughnutChart>
              </div>
            </div>
          </div>
          <div
            data-dashboard-card="target"
            class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <h2 class="text-base font-medium text-n-slate-12">
              {{ periodNoun }}目标完成率
            </h2>
            <p class="mt-1 mb-2 text-xs text-n-slate-10">{{ periodLabel }}</p>
            <template v-if="targetProgress">
              <div class="h-48 mx-auto max-w-[16rem]">
                <CrmDoughnutChart
                  :key="themeSignal"
                  :data="[targetProgress.pct, 100 - targetProgress.pct]"
                  gauge
                  cutout="78%"
                >
                  <template #center>
                    <div class="text-3xl font-bold text-n-slate-12">
                      {{ targetProgress.pct }}%
                    </div>
                  </template>
                </CrmDoughnutChart>
              </div>
              <div class="text-center text-n-slate-11">
                <span class="font-medium text-n-slate-12">
                  {{ targetProgress.done }}
                </span>
                / {{ targetProgress.target }}
              </div>
            </template>
            <div
              v-else
              class="flex flex-col items-center justify-center gap-1 py-10 text-center"
            >
              <span class="i-lucide-target size-6 text-n-slate-10" />
              <p class="text-sm text-n-slate-11">本月尚未设定目标</p>
              <p class="text-xs text-n-slate-10">前往「我的目标」设定</p>
            </div>
          </div>
          <!-- 客户成交排行：按所选期间的成交额排前 5，点一行进客户详情。 -->
          <div
            data-dashboard-card="customers"
            class="p-5 border shadow-sm min-w-0 rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <div class="flex items-center justify-between gap-3 mb-4">
              <h2 class="text-base font-medium text-n-slate-12">
                客户成交排行
              </h2>
              <span class="text-xs text-n-slate-10">{{ periodLabel }}</span>
            </div>
            <div
              v-if="!topCustomers.length"
              class="flex items-center justify-center h-32 text-sm text-n-slate-10"
            >
              这段时间还没有成交
            </div>
            <ul v-else class="flex flex-col">
              <li
                v-for="(c, ci) in topCustomers"
                :key="c.id || `masked-${ci}`"
                class="flex items-center gap-3 px-2 py-2.5 -mx-2 rounded-lg"
                :class="
                  c.masked ? '' : 'cursor-pointer hover:bg-n-alpha-1'
                "
                :title="c.masked ? '' : `${c.name}｜点击查看客户详情`"
                @click="goCustomer(c.id)"
              >
                <span
                  class="flex items-center justify-center text-xs font-medium rounded-full shrink-0 size-9 bg-n-iris-3 text-n-iris-11"
                >
                  {{ rankInitials(c.name) }}
                </span>
                <span class="flex flex-col min-w-0">
                  <span class="text-sm truncate text-n-slate-12">
                    {{ c.name }}
                  </span>
                  <span class="text-xs text-n-slate-10">
                    {{ c.orders }} 单
                  </span>
                </span>
                <span class="flex-1" />
                <span
                  class="text-sm font-semibold tabular-nums whitespace-nowrap text-n-teal-11"
                >
                  {{ moneyYuan(toYuan(c.amount)) }}
                </span>
              </li>
            </ul>
          </div>

          <div
            data-dashboard-card="sources"
            class="p-5 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/45 backdrop-blur-2xl backdrop-saturate-150"
          >
            <h2 class="mb-4 text-base font-medium text-n-slate-12">
              客户来源占比
            </h2>
            <template v-if="!sourceDonut.empty">
              <div class="relative h-40 mx-auto max-w-[12rem]">
                <CrmDoughnutChart
                  :key="themeSignal"
                  :labels="sourceDonut.labels"
                  :data="sourceDonut.data"
                  :colors="sourceDonut.colors"
                >
                  <template #center>
                    <div class="text-xl font-bold text-n-slate-12">
                      {{ sourceDonut.total }}
                    </div>
                    <div class="text-xs text-n-slate-10">客户</div>
                  </template>
                </CrmDoughnutChart>
              </div>
              <div class="flex flex-col gap-1.5 mt-4">
                <div
                  v-for="(label, i) in sourceDonut.labels"
                  :key="label"
                  class="flex items-center gap-2 text-sm"
                >
                  <span
                    class="inline-block rounded-full size-2.5 shrink-0"
                    :style="{ backgroundColor: sourceDonut.colors[i] }"
                  />
                  <span class="truncate text-n-slate-11">{{ label }}</span>
                  <span class="ml-auto font-medium text-n-slate-12">
                    {{ sourceDonut.data[i] }}
                  </span>
                </div>
              </div>
            </template>
            <div
              v-else
              class="flex items-center justify-center h-56 text-sm text-n-slate-10"
            >
              暂无来源数据
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
