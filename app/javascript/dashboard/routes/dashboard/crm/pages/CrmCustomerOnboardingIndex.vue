<script setup>
/* global axios */
import { ref, reactive, computed, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';

const { accountId } = useAccount();
const currentUserId = useMapGetter('getCurrentUserID');

const COUNTRY = [
  ['USA', '🇺🇸 美国'], ['GERMANY', '🇩🇪 德国'], ['UK', '🇬🇧 英国'], ['FRANCE', '🇫🇷 法国'],
  ['ITALY', '🇮🇹 意大利'], ['SPAIN', '🇪🇸 西班牙'], ['CANADA', '🇨🇦 加拿大'], ['AUSTRALIA', '🇦🇺 澳大利亚'],
  ['JAPAN', '🇯🇵 日本'], ['SOUTH_KOREA', '🇰🇷 韩国'], ['INDIA', '🇮🇳 印度'], ['RUSSIA', '🇷🇺 俄罗斯'],
  ['BRAZIL', '🇧🇷 巴西'], ['MEXICO', '🇲🇽 墨西哥'], ['NETHERLANDS', '🇳🇱 荷兰'], ['UAE', '🇦🇪 阿联酋'],
  ['SAUDI_ARABIA', '🇸🇦 沙特阿拉伯'], ['SINGAPORE', '🇸🇬 新加坡'], ['MALAYSIA', '🇲🇾 马来西亚'],
  ['THAILAND', '🇹🇭 泰国'], ['VIETNAM', '🇻🇳 越南'], ['INDONESIA', '🇮🇩 印度尼西亚'],
  ['TURKEY', '🇹🇷 土耳其'], ['SOUTH_AFRICA', '🇿🇦 南非'], ['EGYPT', '🇪🇬 埃及'], ['NIGERIA', '🇳🇬 尼日利亚'],
  ['POLAND', '🇵🇱 波兰'], ['NETHERLANDS', '🇳🇱 荷兰'], ['SWEDEN', '🇸🇪 瑞典'], ['TAIWAN', '🇹🇼 台湾'],
  ['HONG_KONG', '🇭🇰 香港'], ['PAKISTAN', '🇵🇰 巴基斯坦'], ['BANGLADESH', '🇧🇩 孟加拉国'], ['OTHER', '其他'],
];
const CUSTOMER_GROUP = [
  ['KEY_ACCOUNT_WON', '成交重点客户'], ['WON', '成交客户'], ['SAMPLE_WON', '成交样品客户'],
  ['NOT_WON', '未成交客户'], ['SOCIAL_MEDIA', '社媒开发客户'],
];
const PRODUCT_GROUP = [
  ['TABLET', '平板电脑'], ['COMMERCIAL_DISPLAY', '商显'], ['INDUSTRIAL_CONTROL', '工控'],
];
const SOURCE = [
  ['ALIBABA', '阿里巴巴国际站'], ['WEBSITE', '官网'], ['EXHIBITION', '展会'],
  ['REFERRAL', '转介绍'], ['EMAIL', '邮件开发'], ['OTHER', '其他'],
];

const form = reactive({
  name: '',
  tradeCountry: '',
  sourceChannel: '',
  customerGroup: '',
  productGroup: '',
  primaryContactName: '',
  email: '',
  website: '',
});

const emailHit = ref(null);
const nameHits = ref([]);
const submitting = ref(false);
const result = ref(null); // { ok: true, code } | { ok: false, msg }

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

const submit = async () => {
  if (!canSubmit.value) return;
  submitting.value = true;
  result.value = null;
  const payload = {
    name: form.name.trim() || form.primaryContactName.trim(),
    trade_country: form.tradeCountry,
    source_channel: form.sourceChannel || null,
    customer_group: form.customerGroup,
    product_group: form.productGroup,
    primary_contact_name: form.primaryContactName.trim(),
    contact_email: form.email.trim(),
    website: form.website.trim() || null,
    account_owner_id: currentUserId.value,
    is_in_public_pool: false,
    customer_status: 'PROSPECT',
  };
  try {
    const { data } = await axios.post(`${api()}/customers`, {
      customer: payload,
    });
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
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div class="flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <h1 class="text-xl font-medium text-n-slate-12">客户建档</h1>
    </div>

    <div class="flex flex-col w-full max-w-3xl gap-3 px-6 py-5">
      <p class="text-xs text-n-slate-11">
        新客户建档。<strong class="text-n-slate-12">建档后客户自动归你名下（私海）</strong
        >，客户编号自动生成。带 <span class="text-n-ruby-11">*</span> 为必填；同一邮箱只能被一个客户建档。
      </p>

      <!-- 邮箱撞单：阻止 -->
      <div
        v-if="emailHit"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-ruby-8 text-n-ruby-11"
      >
        <span>
          ⛔ 该邮箱已被建档：<strong>{{ emailHit.name }}</strong>
          <template v-if="emailHit.customer_code">（{{ emailHit.customer_code }}）</template>
          · {{ emailHit.owner }}
        </span>
        <span class="text-xs text-n-slate-11">
          无法用相同邮箱重复建档，请换邮箱或联系负责人。
        </span>
      </div>

      <!-- 公司名相似：提醒 -->
      <div
        v-if="!emailHit && nameHits.length"
        class="flex flex-col gap-1 p-3 text-sm border rounded-lg border-n-amber-8 text-n-amber-11"
      >
        <span>⚠️ 发现公司名相似的已有客户（可继续建档，请确认非同一家）：</span>
        <span
          v-for="m in nameHits"
          :key="m.id"
          class="text-xs text-n-slate-11"
        >
          · {{ m.name }}
          <template v-if="m.customer_code">（{{ m.customer_code }}）</template>
          · {{ m.owner }}
        </span>
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
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">国家 <span class="text-n-ruby-11">*</span></span>
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
          <span class="text-xs text-n-slate-11">主要联系人 <span class="text-n-ruby-11">*</span></span>
          <input
            v-model="form.primaryContactName"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="联系人姓名"
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
        <label class="flex flex-col gap-1 sm:col-span-2">
          <span class="text-xs text-n-slate-11">公司网址</span>
          <input
            v-model="form.website"
            class="h-9 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="https://example.com（选填，有助查重）"
          />
        </label>
      </div>

      <div class="flex items-center gap-3 mt-1">
        <button
          class="h-10 px-6 text-sm font-medium text-white rounded-lg bg-n-blue-9 disabled:opacity-50 disabled:cursor-not-allowed"
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
