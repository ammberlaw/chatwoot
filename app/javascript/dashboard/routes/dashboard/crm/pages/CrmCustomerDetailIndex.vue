<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import PisAPI from 'dashboard/api/crm/pis';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';
import CrmStarRating from 'dashboard/components-next/CRM/CrmStarRating.vue';
import DatePicker from 'dashboard/components-next/datepicker/DatePicker.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const customersStore = useCrmCustomersStore();
const { ensureLoaded, groupLabel, sourceLabel } = useCrmOptions();

const customerId = computed(() => route.params.id);
const loading = ref(true);
const data = ref(null);
const editDialogRef = ref(null);

const crmBase = () => `/api/v1/accounts/${accountId.value}/crm`;

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await axios.get(
      `${crmBase()}/customers/${customerId.value}/detail`
    );
    data.value = payload;
  } finally {
    loading.value = false;
  }
};

const customer = computed(() => data.value?.customer || {});
const notes = computed(() => data.value?.notes || []);

// ---- 下次跟进 + 一键加入日程 ----
const nextDate = ref('');
const nextTime = ref('09:00');
const addToSchedule = ref(true);
const savingNext = ref(false);
const pad2 = n => String(n).padStart(2, '0');
const timeOptions = (() => {
  const out = [];
  for (let h = 0; h < 24; h += 1) {
    ['00', '30'].forEach(mm => {
      const v = `${pad2(h)}:${mm}`;
      out.push({ value: v, label: v });
    });
  }
  return out;
})();
// 用客户当前的下次跟进时间回填编辑器。
watch(
  customer,
  c => {
    if (c?.next_follow_up_at) {
      nextDate.value = c.next_follow_up_at.slice(0, 10);
      nextTime.value = c.next_follow_up_at.slice(11, 16) || '09:00';
    }
  },
  { immediate: true }
);
const saveNextFollowUp = async () => {
  if (!nextDate.value) {
    useAlert('请选择下次跟进日期');
    return;
  }
  const startAt = `${nextDate.value}T${nextTime.value}:00`;
  savingNext.value = true;
  try {
    await axios.post(
      `${crmBase()}/customers/${customer.value.id}/schedule_follow_up`,
      { next_follow_up_at: startAt, add_to_schedule: addToSchedule.value }
    );
    await load();
    useAlert(addToSchedule.value ? '下次跟进已保存并加入日程' : '下次跟进已保存');
  } catch {
    useAlert('保存失败');
  } finally {
    savingNext.value = false;
  }
};
const tasks = computed(() => data.value?.tasks || []);
const opportunities = computed(() => data.value?.opportunities || []);
const orders = computed(() => data.value?.orders || []);
const pis = computed(() => data.value?.pis || []);
const quotes = computed(() => data.value?.quotes || []);
const files = computed(() => customer.value.files || []);
const primaryOpp = computed(() => opportunities.value[0] || null);
const latestQuote = computed(() => quotes.value[0] || null);
const openTasks = computed(() =>
  tasks.value.filter(t => t.status !== 'DONE' && t.status !== 'CANCELLED')
);

// ---- 枚举 → 中文（未知回退原值）----
const STAGE = {
  NEEDS_CONFIRMED: '需求确认',
  SAMPLING: '样品中',
  WON: '已成交',
  LOST: '输单',
};
const STATUS = {
  PROSPECT: '潜在客户',
  FOLLOWING: '跟进中',
  WON: '成交客户',
  DORMANT: '休眠客户',
  LOST: '流失客户',
};
const ORDER_STATUS = {
  PENDING_CONFIRMATION: '待确认',
  IN_PRODUCTION: '生产中',
  PENDING_SHIPMENT: '待发货',
  SHIPPED: '已发货',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
};
const PI_STATUS = {
  DRAFT: { label: '草稿', cls: 'bg-n-slate-3 text-n-slate-11' },
  PAID: { label: '已付款', cls: 'bg-n-teal-3 text-n-teal-11' },
  VOID: { label: '已作废', cls: 'bg-n-ruby-3 text-n-ruby-11' },
};

// 导出某张 PI 的 Excel（复用 PI 模块的模板导出）。
const downloadingPiId = ref(null);
const downloadPi = async pi => {
  downloadingPiId.value = pi.id;
  try {
    const { data: blob } = await PisAPI.xlsx(accountId.value, pi.id);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `PI-${pi.pi_no || 'export'}.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  } catch (error) {
    const msg = error?.response?.data;
    useAlert(
      msg instanceof Blob
        ? JSON.parse(await msg.text()).error
        : msg?.error || '导出失败'
    );
  } finally {
    downloadingPiId.value = null;
  }
};
const METHOD = {
  EMAIL: '邮件',
  PHONE: '电话',
  MEETING: '会议',
  WHATSAPP: 'WhatsApp',
  WECHAT: '微信',
};
const RESULT_TAG = {
  INTERESTED: '有意向',
  WAITING_CUSTOMER: '等客户回复',
  WAITING_INTERNAL: '等内部处理',
  INVALID: '无效',
};
const PRODUCT_GROUP = { TABLET: '平板电脑', COMMERCIAL_DISPLAY: '商显工控' };

const countryLabel = code => COUNTRY_LABELS[code] || code || '—';
const stageLabel = code => STAGE[code] || code || '—';
const statusLabel = code => STATUS[code] || code || '—';
const methodLabel = code => METHOD[code] || code;
const resultLabel = code => RESULT_TAG[code] || code;
const dash = v => (v === null || v === undefined || v === '' ? '—' : v);
const fmtDate = v => (v ? new Date(v).toLocaleDateString() : '—');
const money = (micros, currency) => {
  if (micros === null || micros === undefined) return '—';
  const symbol = { CNY: '¥', USD: '$', EUR: '€' }[currency] || '';
  return `${symbol}${Math.round(micros / 1_000_000).toLocaleString()}`;
};
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

// 顶部字段网格
const fields = computed(() => {
  const c = customer.value;
  return [
    { icon: 'i-lucide-building-2', label: '公司', value: dash(c.name) },
    {
      icon: 'i-lucide-flag',
      label: '国家',
      value: countryLabel(c.trade_country),
    },
    { icon: 'i-lucide-briefcase', label: '行业', value: dash(c.industry) },
    {
      icon: 'i-lucide-tag',
      label: '客户分组',
      value: groupLabel(c.customer_group) || '—',
    },
    {
      icon: 'i-lucide-user',
      label: '联系人',
      value: dash(c.primary_contact_name),
    },
    { icon: 'i-lucide-mail', label: '邮箱', value: dash(c.contact_email) },
    {
      icon: 'i-lucide-phone',
      label: '电话/WhatsApp',
      value: dash(c.contact_phone || c.whats_app),
    },
    {
      icon: 'i-lucide-globe',
      label: '来源',
      value: sourceLabel(c.source_channel) || '—',
    },
    {
      icon: 'i-lucide-star',
      label: '客户星级',
      stars: true,
      micros: c.deal_total_amount_micros,
    },
    {
      icon: 'i-lucide-box',
      label: '意向产品',
      value: PRODUCT_GROUP[c.product_group] || '—',
    },
    {
      icon: 'i-lucide-flag-triangle-right',
      label: '当前状态',
      value: statusLabel(c.customer_status),
    },
  ];
});

// 下一步建议：优先取最新跟进的下一步（结果标签/正文），否则最近待办标题。
const nextSuggestion = computed(() => {
  const t = openTasks.value[0];
  if (t) return t.title;
  const n = notes.value[0];
  return n?.result_tag || n?.title || '—';
});

const goBack = () => router.push({ name: 'crm_customers_index' });

// 点击商机/订单 → 跳到对应列表并带 focus，列表加载后自动打开该条。
const goToOpportunity = id =>
  router.push({
    name: 'crm_opportunities_index',
    params: { accountId: accountId.value },
    query: { focus: id },
  });
const goToOrder = id =>
  router.push({
    name: 'crm_sales_orders_index',
    params: { accountId: accountId.value },
    query: { focus: id },
  });

// 详情接口回 snake_case，编辑弹窗 open() 读 camelCase 表单键，故转换后再喂。
const toCamel = obj =>
  Object.fromEntries(
    Object.entries(obj || {}).map(([k, v]) => [
      k.replace(/_([a-z])/g, (_, c) => c.toUpperCase()),
      v,
    ])
  );
const openEdit = () =>
  editDialogRef.value?.open({ ...toCamel(customer.value), files: files.value });

// 弹窗把保存委托给父组件（与客户列表一致）：走 store.update 再重载详情。
const onUpdate = async payload => {
  try {
    await customersStore.update(payload);
    editDialogRef.value?.onSuccess();
    useAlert('已保存');
    await load();
  } catch {
    useAlert('保存失败');
  }
};

onMounted(() => {
  ensureLoaded();
  load();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div v-if="loading" class="py-20 text-sm text-center text-n-slate-10">
      加载中…
    </div>

    <div v-else class="w-full max-w-6xl px-6 py-5 mx-auto">
      <!-- Header -->
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center gap-3">
          <button
            class="p-1.5 rounded-lg text-n-slate-11 hover:bg-n-alpha-1"
            @click="goBack"
          >
            <span class="i-lucide-arrow-left size-5" />
          </button>
          <h1 class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12">
            客户详情
          </h1>
        </div>
        <button
          class="flex items-center gap-1.5 h-9 px-3 text-sm rounded-[9px] border border-n-weak bg-n-solid-1/70 text-n-slate-12 hover:bg-n-alpha-2"
          @click="openEdit"
        >
          <span class="i-lucide-pencil size-4" />
          编辑资料
        </button>
      </div>

      <!-- 顶部客户卡 -->
      <div class="p-5 mb-4 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
        <div class="flex items-start gap-4">
          <div
            class="flex items-center justify-center text-lg font-semibold text-white rounded-xl size-14 shrink-0 bg-n-teal-9"
          >
            {{ initial(customer.name) }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold truncate text-n-slate-12">
                {{ dash(customer.name) }}
              </h2>
              <span
                class="px-2 py-0.5 text-xs rounded-md bg-n-teal-3 text-n-teal-11"
              >
                {{ statusLabel(customer.customer_status) }}
              </span>
            </div>
            <p class="mt-0.5 text-sm text-n-slate-11">
              {{ dash(customer.customer_code) }} · 客户详情页
            </p>
          </div>
        </div>

        <div
          class="grid grid-cols-1 gap-x-8 gap-y-3 mt-5 sm:grid-cols-2 lg:grid-cols-3"
        >
          <div
            v-for="f in fields"
            :key="f.label"
            class="flex items-center gap-2 text-sm min-w-0"
          >
            <span :class="f.icon" class="size-4 text-n-slate-9 shrink-0" />
            <span class="text-n-slate-10 shrink-0">{{ f.label }}：</span>
            <CrmStarRating v-if="f.stars" :micros="f.micros" />
            <span v-else class="truncate text-n-slate-12">{{ f.value }}</span>
          </div>
        </div>
      </div>

      <!-- KPI 卡 -->
      <div class="grid grid-cols-2 gap-4 mb-4 lg:grid-cols-4">
        <div class="p-4 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-phone-call size-4" /> 最近联系
          </div>
          <div class="mt-2 text-lg font-semibold text-n-slate-12">
            {{ fmtDate(customer.last_follow_up_at) }}
          </div>
        </div>
        <div class="p-4 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-file-text size-4" /> 当前状态
          </div>
          <div class="mt-2 text-lg font-semibold text-n-slate-12">
            {{ statusLabel(customer.customer_status) }}
          </div>
        </div>
        <div class="p-4 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-lightbulb size-4" /> 下一步建议
          </div>
          <div class="mt-2 text-sm font-medium truncate text-n-slate-12">
            {{ nextSuggestion }}
          </div>
        </div>
        <div class="p-4 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
          <div class="flex items-center gap-2 text-xs text-n-slate-10">
            <span class="i-lucide-receipt size-4" /> 最近报价
          </div>
          <div class="mt-2 text-lg font-semibold text-n-slate-12">
            {{
              latestQuote
                ? money(
                    latestQuote.total_amount_micros,
                    latestQuote.quote_currency
                  )
                : '—'
            }}
          </div>
        </div>
      </div>

      <!-- 两列主体 -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <!-- 左列 -->
        <div class="flex flex-col gap-4">
          <!-- 下次跟进 + 加入日程 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <div class="flex items-center justify-between mb-3">
              <h3 class="text-sm font-semibold text-n-slate-12">下次跟进</h3>
              <span
                v-if="customer.next_follow_up_at"
                class="text-xs text-n-slate-10"
              >
                当前：{{ customer.next_follow_up_at.slice(0, 16).replace('T', ' ') }}
              </span>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <div class="w-40">
                <DatePicker v-model="nextDate" block :clearable="false" />
              </div>
              <div class="w-28">
                <SelectCard v-model="nextTime" :options="timeOptions" block />
              </div>
              <label class="flex items-center gap-1.5 text-sm text-n-slate-11">
                <input
                  v-model="addToSchedule"
                  type="checkbox"
                  class="accent-n-iris-9"
                />
                加入我的日程
              </label>
              <button
                class="px-3.5 py-2 text-sm font-semibold text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
                :disabled="savingNext"
                @click="saveNextFollowUp"
              >
                {{ savingNext ? '保存中…' : '保存' }}
              </button>
            </div>
          </section>

          <!-- 沟通时间线 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">
              沟通时间线
            </h3>
            <div v-if="!notes.length" class="text-sm text-n-slate-10">
              暂无跟进记录
            </div>
            <div v-else class="flex flex-col gap-4">
              <div
                v-for="n in notes"
                :key="n.id"
                class="relative pl-5 border-l-2 border-n-weak"
              >
                <span
                  class="absolute -left-[5px] top-1.5 rounded-full size-2 bg-n-teal-9"
                />
                <div
                  class="flex items-center gap-2 text-xs font-medium text-n-slate-11"
                >
                  {{ fmtDate(n.created_at) }}
                  <span
                    v-if="n.follow_up_method"
                    class="px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-10"
                  >
                    {{ methodLabel(n.follow_up_method) }}
                  </span>
                  <span v-if="n.owner_name" class="text-n-slate-9">
                    · {{ n.owner_name }}
                  </span>
                </div>
                <div class="mt-1 text-sm font-medium text-n-slate-12">
                  {{ n.title }}
                </div>
                <div
                  v-if="n.body"
                  class="mt-0.5 text-sm text-n-slate-11 whitespace-pre-wrap"
                >
                  {{ n.body }}
                </div>
                <div v-if="n.result_tag" class="mt-1 text-xs text-n-slate-10">
                  跟进结果：{{ resultLabel(n.result_tag) }}
                </div>
              </div>
            </div>
          </section>

          <!-- 商机信息 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-sm font-semibold text-n-slate-12">商机信息</h3>
              <button
                v-if="primaryOpp"
                class="text-xs text-n-iris-11 hover:underline"
                @click="goToOpportunity(primaryOpp.id)"
              >
                查看商机 →
              </button>
            </div>
            <div v-if="!primaryOpp" class="text-sm text-n-slate-10">
              暂无商机
            </div>
            <div
              v-else
              class="grid grid-cols-2 p-2 -m-2 text-sm rounded-lg cursor-pointer gap-y-3 gap-x-4 hover:bg-n-alpha-1"
              @click="goToOpportunity(primaryOpp.id)"
            >
              <div>
                <span class="text-n-slate-10">商机：</span>{{ dash(primaryOpp.name) }}
              </div>
              <div>
                <span class="text-n-slate-10">报价金额：</span>{{ money(primaryOpp.amount_micros, primaryOpp.currency) }}
              </div>
              <div>
                <span class="text-n-slate-10">成交概率：</span>{{
                  primaryOpp.probability != null
                    ? primaryOpp.probability + '%'
                    : '—'
                }}
              </div>
              <div>
                <span class="text-n-slate-10">阶段：</span>{{ stageLabel(primaryOpp.sales_stage) }}
              </div>
              <div>
                <span class="text-n-slate-10">预计成交：</span>{{ fmtDate(primaryOpp.expected_close_date) }}
              </div>
              <div>
                <span class="text-n-slate-10">下一步：</span>{{ dash(primaryOpp.next_action) }}
              </div>
            </div>
          </section>

          <!-- 文件附件 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">文件附件</h3>
            <div v-if="!files.length" class="text-sm text-n-slate-10">
              暂无文件
            </div>
            <a
              v-for="f in files"
              :key="f.id"
              :href="f.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-3 py-2 text-sm border-b last:border-b-0 border-n-weak hover:bg-n-alpha-1"
            >
              <span class="i-lucide-file size-4 text-n-slate-9" />
              <span class="flex-1 truncate text-n-slate-12">{{
                f.filename
              }}</span>
              <span class="text-xs text-n-slate-10">{{ Math.round((f.byte_size || 0) / 1024) }} KB</span>
              <span class="i-lucide-download size-4 text-n-slate-9" />
            </a>
          </section>

          <!-- AI 销售建议（占位，后续接 DeepSeek） -->
          <section
            class="p-5 border border-dashed rounded-2xl border-white/60 bg-n-solid-1/30"
          >
            <h3
              class="flex items-center gap-2 text-sm font-semibold text-n-slate-11"
            >
              <span class="i-lucide-bot size-4" /> AI 销售建议
            </h3>
            <p class="mt-2 text-sm text-n-slate-10">
              即将上线：基于往来与商机自动生成跟进建议。
            </p>
          </section>
        </div>

        <!-- 右列 -->
        <div class="flex flex-col gap-4">
          <!-- 待办任务 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">待办任务</h3>
            <div v-if="!openTasks.length" class="text-sm text-n-slate-10">
              暂无待办
            </div>
            <div
              v-for="t in openTasks"
              :key="t.id"
              class="flex items-start gap-3 py-2.5 border-b last:border-b-0 border-n-weak"
            >
              <span
                class="mt-0.5 i-lucide-circle size-4 text-n-slate-9 shrink-0"
              />
              <div class="flex-1 min-w-0">
                <div class="text-sm text-n-slate-12">{{ t.title }}</div>
                <div class="mt-0.5 text-xs text-n-slate-10">
                  截止：{{ fmtDate(t.due_at) }}
                  <span v-if="t.assignee_name">· {{ t.assignee_name }}</span>
                </div>
              </div>
            </div>
          </section>

          <!-- 样品记录（占位，后续新建样品模块） -->
          <section
            class="p-5 border border-dashed rounded-2xl border-white/60 bg-n-solid-1/30"
          >
            <h3
              class="flex items-center gap-2 text-sm font-semibold text-n-slate-11"
            >
              <span class="i-lucide-package size-4" /> 样品记录
            </h3>
            <p class="mt-2 text-sm text-n-slate-10">
              即将上线：寄样状态、快递单号、客户反馈。
            </p>
          </section>

          <!-- 订单记录 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">订单记录</h3>
            <div v-if="!orders.length" class="text-sm text-n-slate-10">
              暂无订单
            </div>
            <div
              v-for="o in orders"
              :key="o.id"
              class="px-2 -mx-2 py-3 border-b last:border-b-0 border-n-weak rounded-lg cursor-pointer hover:bg-n-alpha-1"
              @click="goToOrder(o.id)"
            >
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-n-iris-11">{{
                  o.order_no
                }}</span>
                <span
                  class="px-2 py-0.5 text-xs rounded-md bg-n-amber-3 text-n-amber-11"
                >
                  {{ ORDER_STATUS[o.status] || o.status }}
                </span>
              </div>
              <div class="mt-1 text-xs text-n-slate-10">
                {{ money(o.order_amount_micros, o.order_currency) }} · 下单
                {{ fmtDate(o.order_date) }}
                <span v-if="o.delivery_date">· 预计出货 {{ fmtDate(o.delivery_date) }}</span>
              </div>
              <div
                v-if="o.files && o.files.length"
                class="flex flex-wrap gap-1.5 mt-2"
                @click.stop
              >
                <a
                  v-for="f in o.files"
                  :key="f.id"
                  :href="f.url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded-md border-n-weak text-n-blue-11 hover:bg-n-alpha-1"
                >
                  <span class="i-lucide-paperclip size-3 shrink-0" />
                  <span class="truncate max-w-[180px]">{{ f.filename }}</span>
                </a>
              </div>
            </div>
          </section>

          <!-- PI 记录 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">PI 记录</h3>
            <div v-if="!pis.length" class="text-sm text-n-slate-10">
              暂无 PI
            </div>
            <div
              v-for="p in pis"
              :key="p.id"
              class="flex items-center justify-between gap-2 py-2.5 border-b last:border-b-0 border-n-weak"
            >
              <div class="min-w-0">
                <div class="flex items-center gap-2">
                  <span class="font-mono text-sm truncate text-n-slate-12">
                    {{ p.pi_no }}
                  </span>
                  <span
                    class="px-2 py-0.5 text-xs rounded-md shrink-0"
                    :class="PI_STATUS[p.status]?.cls"
                  >
                    {{ PI_STATUS[p.status]?.label || p.status }}
                  </span>
                </div>
                <div class="mt-0.5 text-xs text-n-slate-10">
                  {{ money(p.total_amount_micros, p.currency) }} ·
                  {{ fmtDate(p.pi_date) }}
                </div>
              </div>
              <button
                type="button"
                class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-md shrink-0 text-n-iris-11 hover:bg-n-iris-3 disabled:opacity-50"
                :disabled="downloadingPiId === p.id"
                @click="downloadPi(p)"
              >
                <span
                  class="size-3.5"
                  :class="
                    downloadingPiId === p.id
                      ? 'i-lucide-loader-circle animate-spin'
                      : 'i-lucide-download'
                  "
                />
                导出 Excel
              </button>
            </div>
          </section>

          <!-- 报价记录 -->
          <section class="p-5 border border-white/70 rounded-2xl bg-n-solid-1/60 shadow-sm">
            <h3 class="mb-4 text-sm font-semibold text-n-slate-12">报价记录</h3>
            <div v-if="!quotes.length" class="text-sm text-n-slate-10">
              暂无报价
            </div>
            <div
              v-for="q in quotes"
              :key="q.id"
              class="flex items-center justify-between py-2.5 border-b last:border-b-0 border-n-weak"
            >
              <div class="min-w-0">
                <div class="text-sm font-medium truncate text-n-slate-12">
                  {{ q.quote_no }}
                </div>
                <div class="text-xs text-n-slate-10">
                  {{ fmtDate(q.quote_date) }}
                </div>
              </div>
              <div class="text-sm font-semibold text-n-slate-12 shrink-0">
                {{ money(q.total_amount_micros, q.quote_currency) }}
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>

    <CrmCustomerCreateDialog
      ref="editDialogRef"
      @update="onUpdate"
      @refresh="load"
    />
  </div>
</template>
