<script setup>
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CrmAiAPI from 'dashboard/api/crm/ai';

const router = useRouter();

const queryText = ref('');
const loading = ref(false); // 背调进行中
const searching = ref(false); // 按公司名搜候选中
const result = ref(null); // null=未查询；{ status, domain, url, profile, enrichment, db_match }
const candidates = ref([]); // 公司名搜索的候选公司，供用户挑一个再背调

// 真实性判断三态：颜色 + 文案
const LEGIT_MAP = {
  real: {
    label: '像真实运营公司',
    cls: 'bg-n-teal-3 text-n-teal-11',
    icon: 'i-lucide-badge-check',
  },
  suspicious: {
    label: '存疑，需人工核实',
    cls: 'bg-n-ruby-4 text-n-ruby-11',
    icon: 'i-lucide-alert-triangle',
  },
  unknown: {
    label: '信息不足，待核实',
    cls: 'bg-n-alpha-2 text-n-slate-11',
    icon: 'i-lucide-help-circle',
  },
};

const profile = computed(() => result.value?.profile || {});
const legit = computed(
  () => LEGIT_MAP[profile.value.legit] || LEGIT_MAP.unknown
);

// 背调结果字段（官网抓取后 AI 判断）
const FIELDS = [
  { key: 'business', label: '主营业务', icon: 'i-lucide-package' },
  { key: 'industry', label: '所属行业', icon: 'i-lucide-layers' },
  { key: 'size_hint', label: '规模线索', icon: 'i-lucide-users' },
  { key: 'country', label: '国家/地区', icon: 'i-lucide-map-pin' },
];

// Apollo 企业库补全（按域名，不依赖官网可爬）：公司概况硬字段
const enrichment = computed(() => result.value?.enrichment || null);
const enrichLocation = computed(() => {
  const e = enrichment.value;
  return e ? [e.city, e.country].filter(Boolean).join('，') : '';
});

const dbMatch = computed(
  () => result.value?.db_match || { total: 0, visible: [] }
);
const hiddenCount = computed(
  () => dbMatch.value.total - dbMatch.value.visible.length
);

// 输入是否像域名/网址：带协议头，或不含 @、无空格、含点（如 acme.com、https://acme.com/x）。
const looksLikeDomain = v =>
  /^https?:\/\//i.test(v) ||
  (!v.includes('@') && !/\s/.test(v) && v.includes('.'));

// 对一个邮箱/域名直接背调。
const lookup = async query => {
  loading.value = true;
  result.value = null;
  candidates.value = [];
  try {
    const { data } = await CrmAiAPI.companyLookup(query);
    result.value = data;
  } catch (e) {
    useAlert(e?.response?.data?.message || 'AI 背调失败，请稍后再试');
  } finally {
    loading.value = false;
  }
};

// 按公司名搜候选公司（Apollo），列出来让用户挑一个。
const searchByName = async name => {
  searching.value = true;
  result.value = null;
  candidates.value = [];
  try {
    const { data } = await CrmAiAPI.companySearch(name);
    candidates.value = data.candidates || [];
    if (!candidates.value.length) {
      useAlert('没搜到这家公司，换个更完整的名字，或直接用公司域名/邮箱背调');
    }
  } catch (e) {
    useAlert(e?.response?.data?.message || '搜索失败，请稍后再试');
  } finally {
    searching.value = false;
  }
};

// 智能分流：邮箱/域名/网址→直接背调；否则当公司名→先搜候选。
const run = () => {
  const value = queryText.value.trim();
  if (!value) {
    useAlert('请输入邮箱、公司域名或公司名');
    return;
  }
  if (value.includes('@') || looksLikeDomain(value)) {
    lookup(value);
  } else {
    searchByName(value);
  }
};

// 选中某个候选公司→对它的域名背调。
const pickCandidate = candidate => lookup(candidate.domain);

const openCustomer = customer => {
  router.push({
    name: 'crm_customers_index',
    query: { filter: 'private', q: customer.name },
  });
};
</script>

<!-- eslint-disable @intlify/vue-i18n/no-raw-text -->
<template>
  <div
    class="flex flex-col w-full h-full overflow-auto border shadow-lg bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border-white/50 shadow-n-iris-9/5"
  >
    <div class="px-6 pt-6 pb-4 border-b border-n-weak">
      <div class="text-lg font-medium text-n-slate-12">AI 背调</div>
      <div class="mt-0.5 text-xs text-n-slate-10">
        输入客户邮箱、公司域名或公司名，AI 自动抓取官网 + 查询 Apollo
        企业库，判断这家公司做什么、规模多大、是否真实可靠，并补全公司概况
      </div>
    </div>

    <!-- 输入 + 背调按钮：图标绝对定位进框内，按钮贴右侧，整框水平居中 -->
    <div class="flex justify-center w-full px-6 pt-5 pb-1">
      <div class="relative w-full max-w-2xl">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-4 left-4 top-1/2 text-n-slate-10"
        />
        <input
          v-model="queryText"
          type="text"
          name="background-query"
          autocomplete="off"
          placeholder="邮箱 / 公司域名 / 公司名，如 buyer@acme.com、acme.com、Acme Ltd"
          class="reset-base w-full h-11 m-0 pl-11 pr-28 text-sm border rounded-lg outline-none bg-n-solid-1 border-n-weak text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand"
          @keyup.enter="run"
        />
        <button
          class="absolute top-0 bottom-0 right-0 flex items-center gap-1.5 px-5 text-sm font-medium text-white rounded-r-lg outline-none bg-n-brand hover:enabled:brightness-110 focus-visible:brightness-110 disabled:opacity-60"
          :disabled="loading || searching"
          @click="run"
        >
          <span
            :class="
              loading || searching
                ? 'i-lucide-loader-2 animate-spin'
                : 'i-lucide-search-check'
            "
            class="size-4"
          />
          背调
        </button>
      </div>
    </div>

    <!-- 搜索公司名中 -->
    <div
      v-if="searching"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-loader-2 animate-spin size-6" />
      正在搜索公司…
    </div>

    <!-- 背调中 -->
    <div
      v-else-if="loading"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-loader-2 animate-spin size-6" />
      正在抓取官网并分析…
    </div>

    <!-- 公司名候选：挑一个再背调 -->
    <div v-else-if="candidates.length" class="flex flex-col gap-2 px-6 py-5">
      <div class="text-xs text-n-slate-10">
        搜到 {{ candidates.length }} 家同/近名公司，点一个开始背调：
      </div>
      <button
        v-for="(c, i) in candidates"
        :key="i"
        class="flex items-center justify-between w-full gap-3 px-4 py-3 text-left border rounded-xl border-n-weak hover:border-n-brand hover:bg-n-alpha-1"
        @click="pickCandidate(c)"
      >
        <div class="min-w-0">
          <div class="text-sm font-medium truncate text-n-slate-12">
            {{ c.name }}
          </div>
          <div class="text-xs truncate text-n-slate-10">
            {{ c.domain }}
            <span v-if="c.industry || c.country">
              ·
              {{
                [c.industry, [c.city, c.country].filter(Boolean).join('，')]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </span>
          </div>
        </div>
        <span class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-9" />
      </button>
    </div>

    <!-- 初始空态 -->
    <div
      v-else-if="!result"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-9"
    >
      <span class="i-lucide-building-2 size-8" />
      输入邮箱、公司域名或公司名，开始背调
    </div>

    <!-- 无效邮箱 -->
    <div
      v-else-if="result.status === 'invalid'"
      class="flex items-center justify-center flex-1 text-n-slate-10"
    >
      邮箱格式不正确，请重新输入
    </div>

    <!-- 个人/公共邮箱 -->
    <div
      v-else-if="result.status === 'public_domain'"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-user size-8" />
      <div class="text-center">
        <div class="font-medium text-n-slate-11">
          {{ result.domain }} 是个人/公共邮箱
        </div>
        <div class="mt-1 text-xs">没有对应的企业官网，查不到公司背景</div>
      </div>
    </div>

    <!-- 抓不到官网 -->
    <div
      v-else-if="result.status === 'no_site'"
      class="flex flex-col items-center justify-center flex-1 gap-2 text-n-slate-10"
    >
      <span class="i-lucide-unplug size-8" />
      <div class="text-center">
        <div class="font-medium text-n-slate-11">
          没能抓取到 {{ result.domain }} 的官网
        </div>
        <div class="mt-1 text-xs">
          可能对方网站防爬、是纯前端渲染，或该域名没有官网。可手动搜索核实。
        </div>
      </div>
    </div>

    <!-- 背调结果 -->
    <div v-else class="flex flex-col gap-4 px-6 py-5">
      <!-- 头卡：公司名 + 官网 + 真实性徽标 -->
      <div class="p-5 border rounded-2xl border-n-weak bg-n-alpha-1">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <div class="text-base font-semibold truncate text-n-slate-12">
              {{ profile.company_name || result.domain }}
            </div>
            <a
              :href="result.url"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 mt-1 text-xs text-n-brand hover:underline"
            >
              <span class="i-lucide-external-link size-3" />
              {{ result.url }}
            </a>
          </div>
          <span
            class="flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-full shrink-0"
            :class="legit.cls"
          >
            <span :class="legit.icon" class="size-3.5" />
            {{ legit.label }}
          </span>
        </div>

        <div
          v-if="profile.note"
          class="p-3 mt-4 text-sm rounded-lg text-n-slate-12 bg-n-brand/5"
        >
          <span class="font-medium text-n-brand">AI 判断：</span>{{ profile.note }}
        </div>
      </div>

      <!-- 字段网格 -->
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div
          v-for="f in FIELDS"
          :key="f.key"
          class="p-4 border rounded-xl border-n-weak"
        >
          <div class="flex items-center gap-1.5 text-xs text-n-slate-10">
            <span :class="f.icon" class="size-3.5" />
            {{ f.label }}
          </div>
          <div class="mt-1.5 text-sm text-n-slate-12">
            {{ profile[f.key] || '未提及' }}
          </div>
        </div>
      </div>

      <!-- Apollo 企业库：公司概况硬字段（规模/成立/营收/所在地/领英/电话） -->
      <div
        v-if="enrichment"
        class="p-5 border rounded-2xl border-n-iris-6 bg-n-iris-2"
      >
        <div
          class="flex items-center gap-1.5 text-sm font-medium text-n-iris-11"
        >
          <span class="i-lucide-database size-4" />
          Apollo 企业库
        </div>
        <div class="grid grid-cols-2 gap-3 mt-3 sm:grid-cols-4">
          <div v-if="enrichment.employees">
            <div class="text-xs text-n-slate-10">员工规模</div>
            <div class="mt-0.5 text-sm font-medium text-n-slate-12">
              约 {{ enrichment.employees }} 人
            </div>
          </div>
          <div v-if="enrichment.founded_year">
            <div class="text-xs text-n-slate-10">成立年份</div>
            <div class="mt-0.5 text-sm font-medium text-n-slate-12">
              {{ enrichment.founded_year }}
            </div>
          </div>
          <div v-if="enrichment.revenue">
            <div class="text-xs text-n-slate-10">年营收</div>
            <div class="mt-0.5 text-sm font-medium text-n-slate-12">
              {{ enrichment.revenue }}
            </div>
          </div>
          <div v-if="enrichLocation">
            <div class="text-xs text-n-slate-10">所在地</div>
            <div class="mt-0.5 text-sm font-medium text-n-slate-12">
              {{ enrichLocation }}
            </div>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-4 mt-3">
          <a
            v-if="enrichment.linkedin"
            :href="enrichment.linkedin"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 text-xs text-n-brand hover:underline"
          >
            <span class="i-lucide-linkedin size-3.5" />
            领英主页
          </a>
          <span
            v-if="enrichment.phone"
            class="inline-flex items-center gap-1 text-xs text-n-slate-11"
          >
            <span class="i-lucide-phone size-3.5" />
            {{ enrichment.phone }}
          </span>
        </div>
      </div>

      <!-- 查库：该域名是否已建档 -->
      <div
        v-if="dbMatch.total > 0"
        class="p-4 border rounded-xl border-n-amber-6 bg-n-amber-2"
      >
        <div
          class="flex items-center gap-1.5 text-sm font-medium text-n-amber-11"
        >
          <span class="i-lucide-alert-triangle size-4" />
          该域名已在系统建档（共 {{ dbMatch.total }} 家），注意避免重复开发
        </div>
        <div v-if="dbMatch.visible.length" class="mt-3 space-y-1.5">
          <div
            v-for="c in dbMatch.visible"
            :key="c.id"
            class="flex items-center justify-between px-3 py-2 text-sm bg-white rounded-lg cursor-pointer hover:brightness-95"
            @click="openCustomer(c)"
          >
            <span class="font-medium truncate text-n-slate-12">{{
              c.name
            }}</span>
            <span class="flex items-center gap-2 shrink-0 text-n-slate-10">
              <span
                v-if="c.mine"
                class="px-1.5 py-0.5 text-xs rounded-full bg-n-teal-3 text-n-teal-11"
              >
                我的客户
              </span>
              <span class="text-xs">归属 {{ c.owner || '—' }}</span>
              <span class="i-lucide-chevron-right size-4" />
            </span>
          </div>
        </div>
        <div v-if="hiddenCount > 0" class="mt-2 text-xs text-n-amber-11">
          另有 {{ hiddenCount }} 家为同事的客户，无权查看详情
        </div>
      </div>
      <div
        v-else
        class="flex items-center gap-1.5 px-4 py-3 text-sm border rounded-xl border-n-weak text-n-slate-10"
      >
        <span class="i-lucide-badge-check size-4 text-n-teal-11" />
        该域名在系统内还没有建档，是全新客户
      </div>
    </div>
  </div>
</template>
