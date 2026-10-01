<script setup>
// 一键背调（可复用）：抓官网 + Apollo 概况判断公司真伪/概况，一键把结构化字段 + 概况备注
// 交回父组件（建档页 / 编辑客户弹窗都用同一套逻辑）。父组件收到 apply 事件后按规则填自己的表单。
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAiAPI from 'dashboard/api/crm/ai';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';

const props = defineProps({
  // 背调取值优先级：公司网址 → 联系邮箱 → 公司名（由父组件当前表单值传入）。
  name: { type: String, default: '' },
  website: { type: String, default: '' },
  email: { type: String, default: '' },
});

const emit = defineEmits(['apply']);

const bgLoading = ref(false);
const bgResult = ref(null); // { status, domain, url, profile, enrichment, db_match }
const bgCandidates = ref([]); // 按公司名搜到的候选，供挑一个再背调
const bgImported = ref(false); // 本次结果是否已导入（避免重复追加备注）
const bgProfile = computed(() => bgResult.value?.profile || {});
const BG_LEGIT = {
  real: { label: '像真实运营公司', cls: 'bg-n-teal-3 text-n-teal-11' },
  suspicious: { label: '存疑，需人工核实', cls: 'bg-n-ruby-4 text-n-ruby-11' },
  unknown: { label: '信息不足，待核实', cls: 'bg-n-alpha-2 text-n-slate-11' },
};
const bgLegit = computed(
  () => BG_LEGIT[bgProfile.value.legit] || BG_LEGIT.unknown
);
const bgEnrich = computed(() => bgResult.value?.enrichment || null);
const bgFields = [
  { key: 'business', label: '主营业务' },
  { key: 'industry', label: '所属行业' },
  { key: 'size_hint', label: '规模线索' },
  { key: 'country', label: '国家/地区' },
];

const countryOptions = Object.entries(COUNTRY_LABELS).map(([value, label]) => ({
  value,
  label,
}));

// 输入是否像域名/网址：带协议头，或不含 @、无空格、含点。
const bgLooksLikeDomain = v =>
  /^https?:\/\//i.test(v) ||
  (!v.includes('@') && !/\s/.test(v) && v.includes('.'));
const bgQuery = computed(
  () =>
    (props.website || '').trim() ||
    (props.email || '').trim() ||
    (props.name || '').trim()
);

const bgLookup = async query => {
  bgLoading.value = true;
  bgResult.value = null;
  bgCandidates.value = [];
  try {
    const { data } = await CrmAiAPI.companyLookup(query);
    bgResult.value = data;
    bgImported.value = false;
  } catch (e) {
    useAlert(e?.response?.data?.message || 'AI 背调失败，请稍后再试');
  } finally {
    bgLoading.value = false;
  }
};

const runBackgroundCheck = async () => {
  const q = bgQuery.value;
  if (!q) {
    useAlert('请先填公司网址/域名、联系邮箱或公司名');
    return;
  }
  if (bgLooksLikeDomain(q) || q.includes('@')) {
    await bgLookup(q);
    return;
  }
  bgLoading.value = true;
  bgResult.value = null;
  bgCandidates.value = [];
  try {
    const { data } = await CrmAiAPI.companySearch(q);
    bgCandidates.value = data.candidates || [];
    if (!bgCandidates.value.length) {
      useAlert('没搜到这家公司，换公司域名/邮箱再试');
    }
  } catch (e) {
    useAlert(e?.response?.data?.message || 'AI 背调失败，请稍后再试');
  } finally {
    bgLoading.value = false;
  }
};
const pickBgCandidate = candidate => bgLookup(candidate.domain);

// 国家：Apollo 给英文国名，映射到国家代码（代码基本＝英文名大写下划线），少数缩写走别名表。
const COUNTRY_ALIAS = {
  UNITED_STATES: 'USA',
  UNITED_STATES_OF_AMERICA: 'USA',
  US: 'USA',
  AMERICA: 'USA',
  UNITED_KINGDOM: 'UK',
  GREAT_BRITAIN: 'UK',
  ENGLAND: 'UK',
  KOREA: 'SOUTH_KOREA',
  REPUBLIC_OF_KOREA: 'SOUTH_KOREA',
  RUSSIAN_FEDERATION: 'RUSSIA',
  UNITED_ARAB_EMIRATES: 'UAE',
  CZECH_REPUBLIC: 'CZECH',
  CZECHIA: 'CZECH',
  VIET_NAM: 'VIETNAM',
  HONGKONG: 'HONG_KONG',
};
// 「纯中文国名 → 代码」：从 COUNTRY_LABELS 去掉 emoji/空格只留中文，按名字长度倒序
// （先长后短，避免"苏丹"命中"南苏丹"、"几内亚"命中"赤道几内亚"）。
const CN_NAME_TO_CODE = Object.entries(COUNTRY_LABELS)
  .map(([code, label]) => [code, String(label).replace(/[^一-龥]/g, '')])
  .filter(([, cn]) => cn)
  .sort((a, b) => b[1].length - a[1].length);
const countryCodeFromName = raw => {
  const text = String(raw || '').trim();
  if (!text) return '';
  const norm = text
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
  if (countryOptions.some(o => o.value === norm)) return norm;
  if (COUNTRY_ALIAS[norm]) return COUNTRY_ALIAS[norm];
  const hit = CN_NAME_TO_CODE.find(([, cn]) => text.includes(cn));
  return hit ? hit[0] : '';
};

// 概况写进备注的文本块（结构化字段之外的信息，避免丢失）。
const buildBgRemark = () => {
  const p = bgProfile.value;
  const e = bgEnrich.value || {};
  const domain = bgResult.value?.domain;
  const name = p.company_name || e.name || domain;
  const lines = [`【AI 背调】${name}${domain ? `（${domain}）` : ''}`];
  const business = p.business || e.description;
  if (business) lines.push(`主营：${business}`);
  const industry = p.industry || e.industry;
  if (industry) lines.push(`行业：${industry}`);
  const size = [];
  if (e.employees) size.push(`约 ${e.employees} 人`);
  else if (p.size_hint) size.push(p.size_hint);
  if (e.founded_year) size.push(`成立 ${e.founded_year}`);
  if (e.revenue) size.push(`营收 ${e.revenue}`);
  if (size.length) lines.push(`规模：${size.join(' · ')}`);
  const geo = [e.country || p.country, e.city].filter(Boolean).join(' · ');
  if (geo) lines.push(`地区：${geo}`);
  if (p.note) lines.push(`AI 判断：${p.note}`);
  return lines.join('\n');
};

// 一键导入：把背调结果结构化字段 + 备注块交回父组件（由父组件按 setAlways/setIfBlank 规则填表单）。
const importBackground = () => {
  const p = bgProfile.value;
  const e = bgEnrich.value || {};
  emit('apply', {
    name: (p.company_name || e.name || '').trim(),
    website: (
      bgResult.value?.url ||
      e.website ||
      (bgResult.value?.domain ? `https://${bgResult.value.domain}` : '')
    ).trim(),
    address: (e.address || '').trim(),
    linkedin: (e.linkedin || '').trim(),
    countryCode:
      countryCodeFromName(e.country) || countryCodeFromName(p.country),
    remarkBlock: buildBgRemark(),
  });
  bgImported.value = true;
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 h-9 px-3 text-sm rounded-lg border border-n-iris-8 text-n-iris-11 hover:bg-n-iris-3 disabled:opacity-50"
        :disabled="bgLoading"
        @click="runBackgroundCheck"
      >
        <span class="i-lucide-search-check size-4" />
        {{ bgLoading ? '背调中…' : '一键背调' }}
      </button>
      <span class="text-xs text-n-slate-10">
        取 公司网址 / 邮箱 / 公司名，抓官网 + Apollo 企业库判断真伪并补全概况
      </span>
    </div>

    <!-- 公司名搜到多个候选：挑一家再背调 -->
    <div
      v-if="bgCandidates.length"
      class="flex flex-col gap-1 p-2 border rounded-lg border-n-weak bg-n-alpha-1"
    >
      <span class="text-xs text-n-slate-10">挑一家再背调：</span>
      <button
        v-for="(c, i) in bgCandidates"
        :key="i"
        type="button"
        class="flex flex-col items-start px-2 py-1.5 text-left rounded-md hover:bg-n-alpha-2"
        @click="pickBgCandidate(c)"
      >
        <span class="text-sm text-n-slate-12">{{ c.name }}</span>
        <span class="text-xs text-n-slate-10">
          {{ c.domain }}
          <template v-if="c.industry || c.country">
            ·
            {{
              [c.industry, [c.city, c.country].filter(Boolean).join('，')]
                .filter(Boolean)
                .join(' · ')
            }}
          </template>
        </span>
      </button>
    </div>

    <!-- 背调结果卡 -->
    <div
      v-if="bgResult"
      class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-solid-1"
    >
      <span
        v-if="['invalid', 'public_domain', 'no_site'].includes(bgResult.status)"
        class="text-xs text-n-amber-11"
      >
        {{
          bgResult.status === 'public_domain'
            ? `${bgResult.domain} 是个人/公共邮箱，判断不了公司`
            : bgResult.status === 'no_site'
              ? `没抓到 ${bgResult.domain} 的官网，可换公司名或域名再试`
              : '输入无法识别为有效域名 / 邮箱'
        }}
      </span>
      <template v-else>
        <div class="flex flex-wrap items-center gap-2">
          <span
            class="inline-flex items-center px-2 py-0.5 text-xs rounded-md"
            :class="bgLegit.cls"
          >
            {{ bgLegit.label }}
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ bgProfile.company_name || bgResult.domain }}
          </span>
          <a
            v-if="bgResult.url"
            :href="bgResult.url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs break-all text-n-iris-11 hover:underline"
          >
            {{ bgResult.url }}
          </a>
        </div>
        <p v-if="bgProfile.note" class="text-xs text-n-slate-11">
          <span class="font-medium text-n-iris-11">AI 判断：</span
          >{{ bgProfile.note }}
        </p>
        <div class="grid grid-cols-2 gap-x-4 gap-y-1">
          <div
            v-for="f in bgFields"
            v-show="bgProfile[f.key]"
            :key="f.key"
            class="text-xs"
          >
            <span class="text-n-slate-10">{{ f.label }}：</span>
            <span class="text-n-slate-12">{{ bgProfile[f.key] }}</span>
          </div>
          <div v-if="bgEnrich && bgEnrich.employees" class="text-xs">
            <span class="text-n-slate-10">员工规模：</span>
            <span class="text-n-slate-12">约 {{ bgEnrich.employees }} 人</span>
          </div>
          <div v-if="bgEnrich && bgEnrich.founded_year" class="text-xs">
            <span class="text-n-slate-10">成立年份：</span>
            <span class="text-n-slate-12">{{ bgEnrich.founded_year }}</span>
          </div>
        </div>
        <div
          v-if="bgResult.db_match && bgResult.db_match.total"
          class="text-xs text-n-amber-11"
        >
          库里已有 {{ bgResult.db_match.total }} 家相似公司，注意查重
        </div>

        <!-- 一键导入：把背调结果填进上面的表单（公司名/网址刷新，其余填空框，概况写进备注） -->
        <div
          class="flex flex-wrap items-center gap-2 pt-1 mt-1 border-t border-n-weak"
        >
          <button
            type="button"
            class="inline-flex items-center gap-1.5 h-8 px-3 mt-1 text-xs font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="bgImported"
            @click="importBackground"
          >
            <span class="i-lucide-download size-3.5" />
            {{ bgImported ? '已导入' : '一键导入客户信息' }}
          </button>
          <span class="mt-1 text-xs text-n-slate-10">
            公司名/网址用正式值刷新，国家/地址等填入空框，概况写进备注
          </span>
        </div>
      </template>
    </div>
  </div>
</template>
