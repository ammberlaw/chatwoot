<script setup>
/* global axios */
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAiAPI from 'dashboard/api/crm/ai';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import CrmStarRating from 'dashboard/components-next/CRM/CrmStarRating.vue';
import { useCrmOptions } from 'dashboard/composables/useCrmOptions';
import { LocalStorage } from 'shared/helpers/localStorage';

const { accountId } = useAccount();
const currentUserId = useMapGetter('getCurrentUserID');

// 国家：{ value, label } 供可搜索 ComboBox 使用
const countryOptions = Object.entries(COUNTRY_LABELS).map(([value, label]) => ({
  value,
  label,
}));
// 客户分组 / 客户来源：从「客户设置」动态读取（含二级层级），不再写死。
const { ensureLoaded, groupOptions, sourceOptions } = useCrmOptions();
onMounted(ensureLoaded);

const PRODUCT_GROUP = [
  ['TABLET', '平板电脑'],
  ['COMMERCIAL_DISPLAY', '商显工控'],
];
const CONTACT_PREFERENCE = [
  ['EMAIL', '邮件'],
  ['PHONE', '电话'],
  ['WHATSAPP', 'WhatsApp'],
  ['WECHAT', '微信'],
];

// 原生 <select> 换成紫玻璃 SelectCard 的选项：各前置一个空值项，等价原生「选择X」清空项。
const tup = arr => arr.map(([value, label]) => ({ value, label }));
const sourceSelectOptions = computed(() => [
  { value: '', label: '选择来源（选填）' },
  ...sourceOptions.value,
]);
const groupSelectOptions = computed(() => [
  { value: '', label: '选择客户分组' },
  ...groupOptions.value,
]);
const productGroupSelectOptions = [
  { value: '', label: '选择产品分组' },
  ...tup(PRODUCT_GROUP),
];
const prefSelectOptions = [
  { value: '', label: '选择偏好（选填）' },
  ...tup(CONTACT_PREFERENCE),
];

const form = reactive({
  name: '',
  website: '',
  tradeCountry: '',
  customerGroup: '',
  productGroup: '',
  sourceChannel: '',
  address: '',
  linkedin: '',
  primaryContactName: '',
  contactJobTitle: '',
  email: '',
  contactPhone: '',
  wechat: '',
  whatsApp: '',
  alibabaAccount: '',
  contactPreference: '',
  customerRemark: '',
});

// 从邮件身份卡 / 会话联系人面板「建档为客户」跳来时预填（在草稿恢复后应用，见 onMounted）。
const route = useRoute();
const router = useRouter();

const emailHit = ref(null);
const phoneHit = ref(null);
const nameHits = ref([]);
const alibabaHit = ref(null);
const submitting = ref(false);
const result = ref(null);

// 其他联系人（采购/经理等）：每个邮箱建档时挂到本客户，任一邮箱来信都自动归属。
const extraContacts = ref([]);
const addContact = () =>
  extraContacts.value.push({ name: '', jobTitle: '', email: '', phone: '' });
const removeContact = i => extraContacts.value.splice(i, 1);

// ── 未提交草稿持久化 ──
// 建档只有点「建档」才写库；填一半切到别的板块/刷新页面时组件会被销毁，
// 这里把草稿存进 localStorage，回到本页自动回填，建档成功后清除。
// 按 账号+用户 隔离，避免共用机器时串号。
const draftKey = () =>
  `crm:onboarding-draft::${accountId.value}::${currentUserId.value}`;
const draftRestored = ref(false);
const clearDraft = () => LocalStorage.remove(draftKey());

const hasContent = () =>
  Object.values(form).some(v => v && String(v).trim()) ||
  extraContacts.value.length > 0;

const saveDraft = () => {
  if (hasContent()) {
    LocalStorage.set(draftKey(), {
      ...form,
      extraContacts: extraContacts.value,
    });
  } else {
    clearDraft();
  }
};

let saveTimer = null;
watch(
  () => JSON.stringify({ f: form, e: extraContacts.value }),
  () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDraft, 300);
  }
);

onMounted(() => {
  const saved = LocalStorage.get(draftKey());
  if (saved && typeof saved === 'object') {
    Object.keys(form).forEach(k => {
      if (saved[k] != null) form[k] = saved[k];
    });
    if (Array.isArray(saved.extraContacts)) {
      extraContacts.value = saved.extraContacts;
    }
    draftRestored.value = hasContent();
  }
  // 从邮件身份卡 / 会话联系人面板跳来的信息优先于草稿。
  const q = route.query;
  if (q.email) form.email = String(q.email);
  if (q.name) form.primaryContactName = String(q.name);
  if (q.company) form.name = String(q.company);
  if (q.phone) form.contactPhone = String(q.phone);
  // WhatsApp 会话过来的联系人，手机号就是 WhatsApp 号，一并填上。
  if (q.whatsapp) form.whatsApp = String(q.whatsapp);
});

const api = () => `/api/v1/accounts/${accountId.value}/crm`;

// 实时查重：输入停顿 450ms 后查邮箱(精确)+手机/WhatsApp(后 9 位)+公司名(相似)
let dedupeTimer = null;
watch(
  () => [
    form.email,
    form.name,
    form.contactPhone,
    form.whatsApp,
    form.alibabaAccount,
  ],
  () => {
    clearTimeout(dedupeTimer);
    dedupeTimer = setTimeout(async () => {
      const email = form.email.trim();
      const name = form.name.trim();
      const phone = (form.contactPhone || form.whatsApp).trim();
      const alibaba = form.alibabaAccount.trim();
      const noEmail = email.length <= 3 || !email.includes('@');
      if (
        noEmail &&
        name.length < 2 &&
        alibaba.length < 3 &&
        phone.replace(/\D/g, '').length < 8
      ) {
        emailHit.value = null;
        phoneHit.value = null;
        alibabaHit.value = null;
        nameHits.value = [];
        return;
      }
      try {
        const { data } = await axios.get(`${api()}/customers/check_duplicate`, {
          params: { email, name, phone, alibaba_account: alibaba },
        });
        emailHit.value = data.email_hit;
        phoneHit.value = data.phone_hit;
        alibabaHit.value = data.alibaba_hit;
        nameHits.value = data.name_hits || [];
      } catch {
        emailHit.value = null;
        phoneHit.value = null;
        alibabaHit.value = null;
        nameHits.value = [];
      }
    }, 450);
  }
);

// ── 一键背调（复用 AI 背调：抓官网 + Apollo 概况，判断公司真伪/概况）──
const bgLoading = ref(false);
const bgResult = ref(null); // { status, domain, url, profile, enrichment, db_match }
const bgCandidates = ref([]); // 按公司名搜到的候选，供挑一个再背调
const bgImported = ref(false); // 本次背调结果是否已一键导入表单（避免重复追加备注）
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
// 输入是否像域名/网址：带协议头，或不含 @、无空格、含点。
const bgLooksLikeDomain = v =>
  /^https?:\/\//i.test(v) ||
  (!v.includes('@') && !/\s/.test(v) && v.includes('.'));
// 背调取值优先级：公司网址 → 联系邮箱 → 公司名。
const bgQuery = computed(
  () =>
    (form.website || '').trim() ||
    (form.email || '').trim() ||
    (form.name || '').trim()
);
const bgLookup = async query => {
  bgLoading.value = true;
  bgResult.value = null;
  bgCandidates.value = [];
  try {
    const { data } = await CrmAiAPI.companyLookup(query);
    bgResult.value = data;
    bgImported.value = false; // 新结果可再次导入
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
  // 邮箱/域名/网址→直接背调；否则当公司名→先搜候选。
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

// ── 一键导入：把背调结果填进建档表单 ──
// 结构化字段（公司名/网址/国家/地址/领英）取 Apollo 企业库(enrichment)干净值，只填【空字段】不覆盖已填；
// 主营/行业/规模/AI 判断等概念性信息拼成一段写进「备注」。
// 国家：Apollo 给英文国名，映射到我们的国家代码（代码基本＝英文名大写下划线），少数缩写走别名表。
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
  // 1) 干净英文名（Apollo enrichment）：代码基本＝英文名大写下划线，少数缩写走别名。
  const norm = text
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
  if (countryOptions.some(o => o.value === norm)) return norm;
  if (COUNTRY_ALIAS[norm]) return COUNTRY_ALIAS[norm];
  // 2) AI 中文一句话（如"可能来自北马其顿"）：扫描是否含某个中文国名。
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

const importBackground = () => {
  const p = bgProfile.value;
  const e = bgEnrich.value || {};
  const filled = [];
  // 只填空框、不覆盖已填（国家/地址/领英这类你不会先手填的）。
  const setIfBlank = (key, val, label) => {
    const v = String(val || '').trim();
    if (v && !String(form[key]).trim()) {
      form[key] = v;
      filled.push(label);
    }
  };
  // 覆盖刷新（公司名/网址：用背调的正式名/官网替换你输入的原始值，更整齐）。
  const setAlways = (key, val, label) => {
    const v = String(val || '').trim();
    if (v && form[key] !== v) {
      form[key] = v;
      filled.push(label);
    }
  };
  setAlways('name', p.company_name || e.name, '公司名');
  setAlways(
    'website',
    bgResult.value?.url ||
      e.website ||
      (bgResult.value?.domain ? `https://${bgResult.value.domain}` : ''),
    '网址'
  );
  setIfBlank('address', e.address, '地址');
  setIfBlank('linkedin', e.linkedin, 'Linkedin');
  const code = countryCodeFromName(e.country) || countryCodeFromName(p.country);
  if (code && !form.tradeCountry) {
    form.tradeCountry = code;
    filled.push('国家');
  }

  // 概况写进备注：已含上一次的背调块则替换，避免重复堆叠。
  const block = buildBgRemark();
  const stripped = form.customerRemark
    .replace(/【AI 背调】[\s\S]*$/, '')
    .trim();
  form.customerRemark = stripped ? `${stripped}\n\n${block}` : block;
  filled.push('概况→备注');

  bgImported.value = true;
  useAlert(
    filled.length ? `已导入：${filled.join('、')}` : '没有可导入的新信息'
  );
};

// 联系邮箱、手机/WhatsApp、阿里买家账号，至少要有一个：WhatsApp 来的客户往往没邮箱，
// 阿里来的客户邮箱被平台藏了，强制邮箱等于让这两类客户都建不了档。
// 没邮箱时手机号/阿里账号就是查重依据（见 phoneBlocking / alibabaHit）。
const hasContactKey = computed(
  () =>
    !!(
      form.email.trim() ||
      form.contactPhone.trim() ||
      form.whatsApp.trim() ||
      form.alibabaAccount.trim()
    )
);

const missing = computed(() => {
  const m = [];
  if (!form.tradeCountry) m.push('国家');
  if (!form.customerGroup) m.push('客户分组');
  if (!form.productGroup) m.push('产品分组');
  if (!form.primaryContactName.trim()) m.push('主要联系人');
  if (!hasContactKey.value) m.push('联系邮箱 / 手机号 / 阿里买家账号');
  return m;
});

// 手机号撞库：填了邮箱时只提示（公司总机可能多人共用），没邮箱时手机号是唯一身份，撞了就不给建。
const phoneBlocking = computed(() => !!phoneHit.value && !form.email.trim());

const canSubmit = computed(
  () =>
    missing.value.length === 0 &&
    !emailHit.value &&
    !alibabaHit.value &&
    !phoneBlocking.value &&
    !submitting.value
);

const formHasContent = computed(
  () =>
    Object.values(form).some(v => v && String(v).trim()) ||
    extraContacts.value.length > 0
);

const resetForm = () => {
  Object.keys(form).forEach(k => {
    form[k] = '';
  });
  extraContacts.value = [];
  emailHit.value = null;
  phoneHit.value = null;
  nameHits.value = [];
  bgResult.value = null;
  bgCandidates.value = [];
  bgImported.value = false;
  draftRestored.value = false;
  clearDraft();
};

// 手动清空表单（丢弃已恢复的草稿），并清掉上一次的结果提示。
const discardDraft = () => {
  resetForm();
  result.value = null;
};

const trimmed = v => (v && v.trim ? v.trim() : v) || null;

const submit = async () => {
  if (!canSubmit.value) return;
  submitting.value = true;
  result.value = null;
  const payload = {
    name: form.name.trim() || form.primaryContactName.trim(),
    website: trimmed(form.website),
    trade_country: form.tradeCountry,
    customer_group: form.customerGroup,
    product_group: form.productGroup,
    source_channel: form.sourceChannel || null,
    address: trimmed(form.address),
    linkedin: trimmed(form.linkedin),
    primary_contact_name: form.primaryContactName.trim(),
    contact_job_title: trimmed(form.contactJobTitle),
    contact_email: form.email.trim() || null,
    // 从会话联系人面板跳来的：建档后把这条联系人挂到新客户名下，往来邮件/会话自动归属。
    contact_id: route.query.contactId || null,
    contact_phone: trimmed(form.contactPhone),
    wechat: trimmed(form.wechat),
    whats_app: trimmed(form.whatsApp),
    alibaba_account: trimmed(form.alibabaAccount),
    contact_preference: form.contactPreference || null,
    customer_remark: trimmed(form.customerRemark),
    account_owner_id: currentUserId.value,
    is_in_public_pool: false,
    customer_status: 'PROSPECT',
    contacts: extraContacts.value
      .filter(x => x.email.trim())
      .map(x => ({
        name: x.name.trim(),
        job_title: x.jobTitle.trim(),
        email: x.email.trim(),
        phone: x.phone.trim(),
      })),
  };
  try {
    const { data } = await axios.post(`${api()}/customers`, {
      customer: payload,
    });
    result.value = {
      ok: true,
      code: data.customerCode || data.customer_code || '',
    };
    resetForm();
    // 预填参数只用一次：清掉，免得接着建下一个客户时又被填回来、或把同一联系人挂到第二个客户上。
    if (Object.keys(route.query).length) {
      router.replace({ name: route.name, params: route.params });
    }
  } catch (e) {
    result.value = {
      ok: false,
      msg: e.response?.data?.message || e.message || '未知错误',
    };
  } finally {
    submitting.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex-shrink-0 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <h1 class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">客户建档</h1>
    </div>

    <div class="flex flex-col w-full max-w-3xl gap-4 px-4 py-4 sm:px-6 sm:py-5 [.theme-classic_&]:sm:!px-8">
      <div
        v-if="draftRestored"
        class="flex items-center justify-between gap-2 p-3 text-sm border rounded-lg border-n-amber-8 text-n-amber-11"
      >
        <span>已恢复上次未提交的建档内容，可继续填写。</span>
        <button
          type="button"
          class="flex-shrink-0 text-xs underline text-n-slate-11 hover:text-n-slate-12"
          @click="discardDraft"
        >
          清空表单
        </button>
      </div>

      <div
        v-if="emailHit"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        <span>
          该邮箱已被建档：<strong>{{ emailHit.name }}</strong>
          <template v-if="emailHit.customer_code"
            >（{{ emailHit.customer_code }}）</template
          >
          · {{ emailHit.owner }}
        </span>
        <span class="text-xs text-n-slate-11"
          >无法用相同邮箱重复建档，请换邮箱或联系负责人。</span
        >
      </div>

      <div
        v-if="alibabaHit"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        <span>
          该阿里买家账号已被建档：<strong>{{ alibabaHit.name }}</strong>
          <template v-if="alibabaHit.customer_code">
            （{{ alibabaHit.customer_code }}）
          </template>
          · {{ alibabaHit.owner }}
        </span>
        <span class="text-xs text-n-slate-11">
          同一个阿里买家只能被一个人建档，撞上了请联系负责人。
        </span>
      </div>

      <div
        v-if="phoneHit"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg"
        :class="
          phoneBlocking
            ? 'border-n-ruby-8 text-n-ruby-11'
            : 'border-n-amber-8 text-n-amber-11'
        "
      >
        <span>
          该手机号/WhatsApp 已被建档：
          <strong>{{ phoneHit.name }}</strong>
          <template v-if="phoneHit.customer_code">
            （{{ phoneHit.customer_code }}）
          </template>
          · {{ phoneHit.owner }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{
            phoneBlocking
              ? '没填邮箱时手机号就是客户身份，不能重复建档；请补一个邮箱，或联系负责人。'
              : '公司总机可能多人共用，确认不是同一家即可继续建档。'
          }}
        </span>
      </div>

      <div
        v-if="!emailHit && nameHits.length"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-iris-8 text-n-iris-11"
      >
        <span>发现公司名相似的已有客户（可继续建档，请确认非同一家）：</span>
        <span v-for="m in nameHits" :key="m.id" class="text-xs text-n-slate-11">
          · {{ m.name }}
          <template v-if="m.customer_code">（{{ m.customer_code }}）</template>
          · {{ m.owner }}
        </span>
      </div>

      <!-- 基本信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        基本信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">公司名</span>
          <input
            v-model="form.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">公司网址 / 域名</span>
          <input
            v-model="form.website"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="https://example.com（选填，有助查重）"
          />
        </label>

        <!-- 一键背调：抓官网 + Apollo 概况，判断公司真伪与概况 -->
        <div class="flex flex-col gap-2 sm:col-span-2">
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
              取 公司网址 / 邮箱 / 公司名，抓官网 + Apollo
              企业库判断真伪并补全概况
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
              v-if="
                ['invalid', 'public_domain', 'no_site'].includes(
                  bgResult.status
                )
              "
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
                  <span class="text-n-slate-12"
                    >约 {{ bgEnrich.employees }} 人</span
                  >
                </div>
                <div v-if="bgEnrich && bgEnrich.founded_year" class="text-xs">
                  <span class="text-n-slate-10">成立年份：</span>
                  <span class="text-n-slate-12">{{
                    bgEnrich.founded_year
                  }}</span>
                </div>
              </div>
              <div
                v-if="bgResult.db_match && bgResult.db_match.total"
                class="text-xs text-n-amber-11"
              >
                库里已有 {{ bgResult.db_match.total }} 家相似公司，注意查重
              </div>

              <!-- 一键导入：把背调结果填进上面的建档表单（只填空字段，概况写进备注） -->
              <div
                class="flex flex-wrap items-center gap-2 pt-1 mt-1 border-t border-n-weak"
              >
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 h-8 px-3 mt-1 text-xs font-medium text-white rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-50"
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

        <!-- 备注 -->
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">备注</span>
          <textarea
            v-model="form.customerRemark"
            rows="3"
            class="px-3 py-2 text-sm border rounded-lg outline-none resize-y border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="客户补充信息、跟进注意事项等（选填）"
          />
        </label>
      </div>

      <!-- 业务信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        业务信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >国家地区 <span class="text-n-ruby-11">*</span></span
          >
          <ComboBox
            v-model="form.tradeCountry"
            :options="countryOptions"
            placeholder="选择国家/地区"
            search-placeholder="搜索国家/地区"
          />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">客户来源</span>
          <SelectCard
            v-model="form.sourceChannel"
            :options="sourceSelectOptions"
            block
          />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >客户分组 <span class="text-n-ruby-11">*</span></span
          >
          <SelectCard
            v-model="form.customerGroup"
            :options="groupSelectOptions"
            block
          />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >产品分组 <span class="text-n-ruby-11">*</span></span
          >
          <SelectCard
            v-model="form.productGroup"
            :options="productGroupSelectOptions"
            block
          />
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">客户星级</span>
          <div class="flex items-center gap-2 h-9">
            <CrmStarRating :micros="0" size="md" />
            <span class="text-xs text-n-slate-10"
              >系统按累计成交额自动评定</span
            >
          </div>
        </div>
      </div>

      <!-- 联系信息 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        联系信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11"
            >主要联系人 <span class="text-n-ruby-11">*</span></span
          >
          <input
            v-model="form.primaryContactName"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="联系人姓名"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">职位</span>
          <input
            v-model="form.contactJobTitle"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            联系邮箱
            <span
              v-if="!form.contactPhone.trim() && !form.whatsApp.trim()"
              class="text-n-ruby-11"
              >*</span
            >
          </span>
          <input
            v-model="form.email"
            class="h-9 px-3 text-sm border rounded-lg bg-n-solid-1 text-n-slate-12"
            :class="emailHit ? 'border-n-ruby-8' : 'border-n-weak'"
            placeholder="buyer@example.com"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">
            联系电话
            <span v-if="!form.email.trim()" class="text-n-ruby-11">*</span>
          </span>
          <input
            v-model="form.contactPhone"
            class="h-9 px-3 text-sm border rounded-lg bg-n-solid-1 text-n-slate-12"
            :class="phoneHit ? 'border-n-ruby-8' : 'border-n-weak'"
            placeholder="+1 555 000 0000"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">WhatsApp</span>
          <input
            v-model="form.whatsApp"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="WhatsApp 号"
          />
        </label>
        <label class="flex flex-col gap-1">
          <!-- 阿里来源客户平台把邮箱藏了，买家账号是多店铺之间唯一能对得上的身份 -->
          <span class="text-xs text-n-slate-11">阿里买家账号</span>
          <input
            v-model="form.alibabaAccount"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
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
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">Linkedin</span>
          <input
            v-model="form.linkedin"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="Linkedin 链接"
          />
        </label>
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">联系偏好</span>
          <SelectCard
            v-model="form.contactPreference"
            :options="prefSelectOptions"
            block
          />
        </div>
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">地址</span>
          <input
            v-model="form.address"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="客户地址（选填）"
          />
        </label>
      </div>

      <!-- 其他联系人（采购/经理等）：多个邮箱一并录入，任一来信都自动归属本客户 -->
      <div
        class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
      >
        其他联系人
      </div>
      <p class="-mt-2 text-xs text-n-slate-10">
        采购、经理等其他邮箱可一并录入；任一邮箱来信都会自动识别归属本客户。
      </p>
      <div class="flex flex-col gap-2">
        <div
          v-for="(ct, i) in extraContacts"
          :key="i"
          class="grid grid-cols-1 gap-2 sm:grid-cols-12 sm:items-center"
        >
          <input
            v-model="ct.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="姓名"
          />
          <input
            v-model="ct.jobTitle"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="职位"
          />
          <input
            v-model="ct.email"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-3"
            placeholder="邮箱"
          />
          <input
            v-model="ct.phone"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 sm:col-span-2"
            placeholder="电话（选填）"
          />
          <button
            type="button"
            class="h-9 text-xs rounded-lg text-n-ruby-11 hover:bg-n-ruby-2 sm:col-span-1"
            @click="removeContact(i)"
          >
            删除
          </button>
        </div>
        <button
          type="button"
          class="self-start h-9 px-3 text-sm border border-dashed rounded-lg border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
          @click="addContact"
        >
          + 添加联系人
        </button>
      </div>

      <div class="flex flex-wrap items-center gap-3 mt-1">
        <button
          class="h-10 px-6 text-sm font-medium text-white transition-colors rounded-lg bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!canSubmit"
          @click="submit"
        >
          {{ submitting ? '建档中…' : '建档' }}
        </button>
        <button
          v-if="formHasContent"
          type="button"
          class="h-10 px-4 text-sm font-medium transition-colors border rounded-lg text-n-slate-11 border-n-weak hover:bg-n-alpha-1"
          @click="discardDraft"
        >
          清空
        </button>
        <span v-if="missing.length" class="text-xs text-n-slate-11">
          请填写：{{ missing.join('、') }}
        </span>
      </div>

      <div
        v-if="result?.ok"
        class="p-3 text-sm border rounded-lg border-n-teal-8 text-n-teal-11"
      >
        建档成功<template v-if="result.code">
          ，客户编号 {{ result.code }} </template
        >，已归入你的私海。可继续建下一个。
      </div>
      <div
        v-else-if="result && !result.ok"
        class="p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        建档失败：{{ result.msg }}
      </div>
    </div>
  </div>
</template>
