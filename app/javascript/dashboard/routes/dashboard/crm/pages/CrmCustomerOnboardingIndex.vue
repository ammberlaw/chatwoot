<script setup>
/* global axios */
import { ref, reactive, computed, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';

const { accountId } = useAccount();
const currentUserId = useMapGetter('getCurrentUserID');

// 国家：[码, '国旗 中文名'] 对，供 <option> 遍历
const COUNTRY = Object.entries(COUNTRY_LABELS);
const CUSTOMER_GROUP = [
  ['KEY_ACCOUNT_WON', '成交重点客户'], ['WON', '成交客户'], ['SAMPLE_WON', '成交样品客户'],
  ['NOT_WON', '未成交客户'], ['SOCIAL_MEDIA', '社媒开发客户'],
];
const PRODUCT_GROUP = [
  ['TABLET', '平板电脑'], ['COMMERCIAL_DISPLAY', '商显工控'],
];
const SOURCE = [
  ['ALIBABA', '阿里巴巴国际站'], ['WEBSITE', '官网'], ['EXHIBITION', '展会'],
  ['EMAIL', '邮件开发'], ['SOCIAL_MEDIA', '社媒开发'], ['OTHER', '其他'],
];
const LEVEL = [['A', 'A'], ['B', 'B'], ['C', 'C'], ['D', 'D']];
const CONTACT_PREFERENCE = [
  ['EMAIL', '邮件'], ['PHONE', '电话'], ['WHATSAPP', 'WhatsApp'], ['WECHAT', '微信'],
];

const form = reactive({
  name: '',
  website: '',
  tradeCountry: '',
  customerGroup: '',
  productGroup: '',
  sourceChannel: '',
  customerLevel: '',
  address: '',
  linkedin: '',
  primaryContactName: '',
  contactJobTitle: '',
  email: '',
  contactPhone: '',
  wechat: '',
  whatsApp: '',
  contactPreference: '',
});

const emailHit = ref(null);
const nameHits = ref([]);
const submitting = ref(false);
const result = ref(null);

const api = () => `/api/v1/accounts/${accountId.value}/crm`;

// 实时查重：输入停顿 450ms 后查邮箱(精确)+公司名(相似)
let dedupeTimer = null;
watch(
  () => [form.email, form.name],
  () => {
    clearTimeout(dedupeTimer);
    dedupeTimer = setTimeout(async () => {
      const email = form.email.trim();
      const name = form.name.trim();
      if ((email.length <= 3 || !email.includes('@')) && name.length < 2) {
        emailHit.value = null;
        nameHits.value = [];
        return;
      }
      try {
        const { data } = await axios.get(`${api()}/customers/check_duplicate`, {
          params: { email, name },
        });
        emailHit.value = data.email_hit;
        nameHits.value = data.name_hits || [];
      } catch {
        emailHit.value = null;
        nameHits.value = [];
      }
    }, 450);
  }
);

const missing = computed(() => {
  const m = [];
  if (!form.tradeCountry) m.push('国家');
  if (!form.customerGroup) m.push('客户分组');
  if (!form.productGroup) m.push('产品分组');
  if (!form.primaryContactName.trim()) m.push('主要联系人');
  if (!form.email.trim()) m.push('联系邮箱');
  return m;
});

const canSubmit = computed(
  () => missing.value.length === 0 && !emailHit.value && !submitting.value
);

const resetForm = () => {
  Object.keys(form).forEach(k => {
    form[k] = '';
  });
  emailHit.value = null;
  nameHits.value = [];
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
    customer_level: form.customerLevel || null,
    address: trimmed(form.address),
    linkedin: trimmed(form.linkedin),
    primary_contact_name: form.primaryContactName.trim(),
    contact_job_title: trimmed(form.contactJobTitle),
    contact_email: form.email.trim(),
    contact_phone: trimmed(form.contactPhone),
    wechat: trimmed(form.wechat),
    whats_app: trimmed(form.whatsApp),
    contact_preference: form.contactPreference || null,
    account_owner_id: currentUserId.value,
    is_in_public_pool: false,
    customer_status: 'PROSPECT',
  };
  try {
    const { data } = await axios.post(`${api()}/customers`, { customer: payload });
    result.value = { ok: true, code: data.customerCode || data.customer_code || '' };
    resetForm();
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
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div class="flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">客户建档</h1>
    </div>

    <div class="flex flex-col w-full max-w-3xl gap-4 px-6 py-5">
      <p class="text-xs text-n-slate-11">
        新客户建档。<strong class="text-n-slate-12">建档后客户自动归你名下（私海）</strong
        >，客户编号自动生成。带 <span class="text-n-ruby-11">*</span> 为必填；同一邮箱只能被一个客户建档。
      </p>

      <div
        v-if="emailHit"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        <span>
          ⛔ 该邮箱已被建档：<strong>{{ emailHit.name }}</strong>
          <template v-if="emailHit.customer_code">（{{ emailHit.customer_code }}）</template>
          · {{ emailHit.owner }}
        </span>
        <span class="text-xs text-n-slate-11">无法用相同邮箱重复建档，请换邮箱或联系负责人。</span>
      </div>

      <div
        v-if="!emailHit && nameHits.length"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-iris-8 text-n-iris-11"
      >
        <span>⚠️ 发现公司名相似的已有客户（可继续建档，请确认非同一家）：</span>
        <span v-for="m in nameHits" :key="m.id" class="text-xs text-n-slate-11">
          · {{ m.name }}
          <template v-if="m.customer_code">（{{ m.customer_code }}）</template>
          · {{ m.owner }}
        </span>
      </div>

      <!-- 基本信息 -->
      <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        基本信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">公司名</span>
          <input
            v-model="form.name"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="例如：ABC Trading Co., Ltd.（选填）"
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
      </div>

      <!-- 业务信息 -->
      <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        业务信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">国家地区 <span class="text-n-ruby-11">*</span></span>
          <select
            v-model="form.tradeCountry"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择国家/地区</option>
            <option v-for="[val, lab] in COUNTRY" :key="val" :value="val">{{ lab }}</option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">客户来源</span>
          <select
            v-model="form.sourceChannel"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择来源（选填）</option>
            <option v-for="[val, lab] in SOURCE" :key="val" :value="val">{{ lab }}</option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">客户分组 <span class="text-n-ruby-11">*</span></span>
          <select
            v-model="form.customerGroup"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择客户分组</option>
            <option v-for="[val, lab] in CUSTOMER_GROUP" :key="val" :value="val">{{ lab }}</option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">产品分组 <span class="text-n-ruby-11">*</span></span>
          <select
            v-model="form.productGroup"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择产品分组</option>
            <option v-for="[val, lab] in PRODUCT_GROUP" :key="val" :value="val">{{ lab }}</option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">客户等级</span>
          <select
            v-model="form.customerLevel"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择等级（选填）</option>
            <option v-for="[val, lab] in LEVEL" :key="val" :value="val">{{ lab }}</option>
          </select>
        </label>
      </div>

      <!-- 联系信息 -->
      <div class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        联系信息
      </div>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">主要联系人 <span class="text-n-ruby-11">*</span></span>
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
            placeholder="如 采购经理"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">联系邮箱 <span class="text-n-ruby-11">*</span></span>
          <input
            v-model="form.email"
            class="h-9 px-3 text-sm border rounded-lg bg-n-solid-1 text-n-slate-12"
            :class="emailHit ? 'border-n-ruby-8' : 'border-n-weak'"
            placeholder="buyer@example.com"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">联系电话</span>
          <input
            v-model="form.contactPhone"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
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
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">联系偏好</span>
          <select
            v-model="form.contactPreference"
            class="h-9 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option value="">选择偏好（选填）</option>
            <option v-for="[val, lab] in CONTACT_PREFERENCE" :key="val" :value="val">
              {{ lab }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">地址</span>
          <input
            v-model="form.address"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="客户地址（选填）"
          />
        </label>
      </div>

      <div class="flex items-center gap-3 mt-1">
        <button
          class="h-10 px-6 text-sm font-medium text-white transition-colors rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!canSubmit"
          @click="submit"
        >
          {{ submitting ? '建档中…' : '建档' }}
        </button>
        <span v-if="missing.length" class="text-xs text-n-slate-11">
          请填写：{{ missing.join('、') }}
        </span>
      </div>

      <div
        v-if="result?.ok"
        class="p-3 text-sm border rounded-lg border-n-teal-8 text-n-teal-11"
      >
        ✅ 建档成功<template v-if="result.code">，客户编号 {{ result.code }}</template
        >，已归入你的私海。可继续建下一个。
      </div>
      <div
        v-else-if="result && !result.ok"
        class="p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        ❌ 建档失败：{{ result.msg }}
      </div>
    </div>
  </div>
</template>
