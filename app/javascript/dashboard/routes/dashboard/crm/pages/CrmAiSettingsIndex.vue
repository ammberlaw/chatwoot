<script setup>
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAiSettingsAPI from 'dashboard/api/crm/aiSettings';
import CrmAgentsAPI from 'dashboard/api/crm/crmAgents';
import { useAccount } from 'dashboard/composables/useAccount';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const { t } = useI18n();
const activeTab = ref('connection');
const copy = key => t(`CRM.AI_SETTINGS.LAYOUT.${key}`);
const tabs = ['connection', 'features', 'usage'];
const panelCls = 'rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6';

// 常见 OpenAI 兼容供应商预设（选后自动填端点，仍可手改）。
const PROVIDERS = [
  {
    label: 'DeepSeek',
    base: 'https://api.deepseek.com/v1',
    model: 'deepseek-chat',
  },
  {
    label: '阿里通义千问',
    base: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  },
  {
    label: '月之暗面 Kimi',
    base: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
  },
  { label: 'OpenAI', base: 'https://api.openai.com/v1', model: 'gpt-4o-mini' },
  { label: '自定义', base: '', model: '' },
];

const form = reactive({
  apiKey: '',
  model: 'deepseek-chat',
  apiBase: 'https://api.deepseek.com/v1',
  apolloKey: '',
  apolloMonthlyLimit: null,
  apolloUserLimit: null,
  // 个别人的单独额度 { 用户id(字符串) => 条数 }。留空＝跟随「每人上限」。
  apolloUserLimits: {},
  // 公司级默认初筛条件：新建拓客任务时自动带上。
  leadDefaultCriteria: '',
  // 谁能用 CRM 的 AI 助手（管理员/副管恒可用，不必列进来）
  agentUserIds: [],
  // 陌生来信自动背调+建档+起草回复（会自动花模型调用，默认关）
  inquiryTriageEnabled: false,
  autoDraftReplyEnabled: false,
  autoDraftUserIds: [],
});
const { accountId } = useAccount();
// 可选成员：AI 助手的使用名单从这里挑
const members = ref([]);
const loadMembers = async () => {
  try {
    const { data } = await CrmAgentsAPI.get(accountId.value);
    members.value = data?.payload || data || [];
  } catch {
    members.value = [];
  }
};
const toggleAgentUser = id => {
  const key = String(id);
  form.agentUserIds = form.agentUserIds.includes(key)
    ? form.agentUserIds.filter(x => x !== key)
    : [...form.agentUserIds, key];
};

// 预写回复的试用名单。与「AI 助手开放给谁」分开：助手是人主动去问（问了才花钱），
// 预写是客户一来信就自动跑，成本和风险都更高，所以要能单独圈人先试。
const toggleAutoDraftUser = id => {
  const key = String(id);
  form.autoDraftUserIds = form.autoDraftUserIds.includes(key)
    ? form.autoDraftUserIds.filter(x => x !== key)
    : [...form.autoDraftUserIds, key];
};

const configured = ref(false);
const keyHint = ref(null);
const apolloConfigured = ref(false);
// 本月用量：开了自动初筛之后它会自己跑、自己花钱，得看得到花在哪
const usage = ref(null);
// 刚上线那几天量很小，一律换算成「万」会显示成 0.0 万，看着像没在用
const tokenText = n => {
  const v = Number(n) || 0;
  return v < 10000 ? String(v) : `${(v / 10000).toFixed(1)} 万`;
};
const apolloKeyHint = ref(null);
// Apollo 积分用量。Apollo 没有查余额的接口，这是我们自己记的账。
const apolloUsage = ref({});

// 按人用量：{ user_id => { unlocked, contact_fetch, bg_check, limit } }。
// 后端原来只给 { id => 解锁数 }，页面上既没名字也看不出抓了多少联系人、
// 点了多少次背调——而那两项一旦 Apollo 改计费规则就是下一个窟窿（用户 2026-11-10）。
const usageByUser = computed(() => {
  const map = {};
  (apolloUsage.value.by_user || []).forEach(r => {
    map[r.user_id] = r;
  });
  return map;
});
// 本月 AI 用量，按用途分（初筛/背调/简报/画像）。只摆 token 数不折钱——
// 单价随模型变，折算出来很快过期。
const aiUsage = ref({});
const AI_PURPOSES = {
  lead_screen: '线索初筛',
  lead_bg: '线索背调',
  lead_digest: '每日简报',
  lead_profile: '客户画像',
};
const aiUsageRows = computed(() =>
  Object.entries(aiUsage.value).map(([k, v]) => ({
    key: k,
    label: AI_PURPOSES[k] || k,
    calls: v.calls,
    tokens: (v.input || 0) + (v.output || 0),
  }))
);
const loading = ref(true);
const busy = ref(false);
const testing = ref(false);
const testResult = ref(null); // { ok, message }

// 当前端点匹配到的供应商名（用于下拉高亮）；没匹配到即「自定义」。
const activeProvider = computed(
  () => PROVIDERS.find(p => p.base === form.apiBase)?.label || '自定义'
);

const providerOptions = computed(() =>
  PROVIDERS.map(p => ({ value: p.label, label: p.label }))
);

const applyProvider = label => {
  const p = PROVIDERS.find(item => item.label === label);
  if (!p || p.label === '自定义') return;
  form.apiBase = p.base;
  form.model = p.model;
  testResult.value = null;
};

onMounted(async () => {
  try {
    const { data } = await CrmAiSettingsAPI.get();
    configured.value = data.configured;
    keyHint.value = data.key_hint;
    apolloConfigured.value = data.apollo_configured;
    apolloKeyHint.value = data.apollo_key_hint;
    apolloUsage.value = data.apollo_usage || {};
    form.apolloMonthlyLimit = data.apollo_monthly_limit;
    form.apolloUserLimit = data.apollo_user_limit;
    form.apolloUserLimits = { ...(data.apollo_user_limits || {}) };
    form.leadDefaultCriteria = data.lead_default_criteria || '';
    aiUsage.value = data.ai_usage || {};
    form.model = data.model || 'deepseek-chat';
    form.apiBase = data.api_base || 'https://api.deepseek.com/v1';
    form.agentUserIds = (data.agent_user_ids || []).map(String);
    form.inquiryTriageEnabled = !!data.inquiry_triage_enabled;
    form.autoDraftReplyEnabled = !!data.auto_draft_reply_enabled;
    form.autoDraftUserIds = (data.auto_draft_user_ids || []).map(String);
    usage.value = data.usage || null;
    await loadMembers();
  } catch {
    useAlert(t('CRM.AI_SETTINGS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
});

// 表单当前值（apiKey 留空表示沿用已存 key）。
const payload = () => ({
  api_key: form.apiKey.trim() || undefined,
  api_base: form.apiBase.trim() || undefined,
  model: form.model.trim() || undefined,
});

const save = async () => {
  busy.value = true;
  try {
    const { data } = await CrmAiSettingsAPI.updateSetting({
      setting: {
        api_key: form.apiKey.trim(),
        model: form.model.trim() || 'deepseek-chat',
        api_base: form.apiBase.trim(),
        apollo_api_key: form.apolloKey.trim(),
        // 留空 = 不限额。别写 0，0 是「一条都不让解」。
        apollo_monthly_limit: form.apolloMonthlyLimit || null,
        apollo_user_limit: form.apolloUserLimit || null,
        // 清掉空值再提交，否则会把「跟随默认」存成 0（0 = 一条都不让解）。
        lead_default_criteria: form.leadDefaultCriteria.trim(),
        apollo_user_limits: Object.fromEntries(
          Object.entries(form.apolloUserLimits).filter(([, v]) => Number(v) > 0)
        ),
        agent_user_ids: form.agentUserIds.map(Number),
        inquiry_triage_enabled: form.inquiryTriageEnabled,
        auto_draft_reply_enabled: form.autoDraftReplyEnabled,
        auto_draft_user_ids: form.autoDraftUserIds.map(Number),
      },
    });
    configured.value = data.configured;
    keyHint.value = data.key_hint;
    apolloConfigured.value = data.apollo_configured;
    apolloKeyHint.value = data.apollo_key_hint;
    form.apiKey = ''; // 存完清空输入，回到「已配置 ••••xxxx」态
    form.apolloKey = '';
    useAlert(t('CRM.AI_SETTINGS.SAVED'));
  } catch {
    useAlert(t('CRM.AI_SETTINGS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const testConnection = async () => {
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await CrmAiSettingsAPI.test(payload());
    testResult.value = { ok: true, message: data.message };
  } catch (e) {
    testResult.value = {
      ok: false,
      message: e?.response?.data?.message || t('CRM.AI_SETTINGS.TEST_FAILED'),
    };
  } finally {
    testing.value = false;
  }
};

const fieldCls =
  'h-10 w-full min-w-0 px-3 text-label font-normal border rounded-lg border-n-weak bg-n-alpha-1 text-n-slate-12 focus:outline-none focus:border-n-brand';
</script>

<template>
  <CrmSettingsLayout
    width="wide"
    :title="t('CRM.AI_SETTINGS.HEADER')"
    :description="copy('SUBTITLE')"
  >
    <template #actions>
      <Button
        class="shrink-0"
        :label="t('CRM.AI_SETTINGS.SAVE')"
        icon="i-lucide-check"
        color="iris"
        :is-disabled="busy || loading"
        @click="save"
      />
    </template>
    <div
      v-if="loading"
      class="flex flex-1 items-center justify-center text-label text-n-slate-11"
    >
      {{ t('CRM.AI_SETTINGS.LOADING') }}
    </div>
    <div v-else>
      <div class="w-full">
        <nav
          class="mb-6 flex w-fit max-w-full gap-1 overflow-x-auto rounded-xl bg-n-alpha-2 p-1"
          :aria-label="copy('NAV')"
        >
          <button
            v-for="tab in tabs"
            :key="tab"
            type="button"
            :aria-pressed="activeTab === tab"
            class="min-h-10 shrink-0 rounded-lg px-4 text-label transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-slate-10"
            :class="
              activeTab === tab
                ? 'bg-n-slate-12 text-n-solid-1 shadow-sm'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="activeTab = tab"
          >
            {{ copy(tab) }}
          </button>
        </nav>

        <div
          v-show="activeTab === 'connection'"
          class="grid items-start gap-5 lg:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)]"
        >
          <section :class="panelCls" aria-labelledby="model-connection-heading">
            <div class="mb-6 flex items-center justify-between gap-3">
              <h2
                id="model-connection-heading"
                class="text-heading-2 text-n-slate-12"
              >
                {{ copy('MODEL_CONNECTION') }}
              </h2>
              <span
                class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-label-small text-n-slate-11"
                >{{ copy('SHARED') }}</span
              >
            </div>
            <div class="grid gap-5 sm:grid-cols-2">
              <div class="flex min-w-0 flex-col gap-2">
                <label id="provider-label" class="text-label text-n-slate-12">{{
                  t('CRM.AI_SETTINGS.PROVIDER')
                }}</label>
                <SelectCard
                  :model-value="activeProvider"
                  :options="providerOptions"
                  trigger-class="w-full"
                  aria-labelledby="provider-label"
                  @update:model-value="applyProvider"
                />
              </div>
              <label class="flex min-w-0 flex-col gap-2">
                <span class="text-label text-n-slate-12">{{
                  t('CRM.AI_SETTINGS.MODEL')
                }}</span>
                <input v-model="form.model" type="text" :class="fieldCls" />
              </label>
              <label class="flex min-w-0 flex-col gap-2 sm:col-span-2">
                <span class="flex flex-wrap items-center justify-between gap-2">
                  <span class="text-label text-n-slate-12">{{
                    t('CRM.AI_SETTINGS.API_KEY')
                  }}</span>
                  <span
                    v-if="configured"
                    class="inline-flex items-center gap-1 text-label-small text-n-slate-11"
                    ><Icon icon="i-lucide-check-circle-2" class="size-3.5" />{{
                      t('CRM.AI_SETTINGS.KEY_CONFIGURED', { hint: keyHint })
                    }}</span
                  >
                </span>
                <input
                  v-model="form.apiKey"
                  type="password"
                  autocomplete="off"
                  :placeholder="
                    configured
                      ? copy('KEY_SET')
                      : t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_NEW')
                  "
                  :class="fieldCls"
                />
              </label>
            </div>
            <p
              class="mb-0 mt-3 text-label-small leading-relaxed text-n-slate-11"
            >
              {{ copy('KEY_NOTE') }}
            </p>
            <details class="group mt-6 border-t border-n-weak pt-4">
              <summary
                class="flex min-h-10 cursor-pointer list-none items-center justify-between text-label text-n-slate-11 [&::-webkit-details-marker]:hidden"
              >
                {{ copy('ADVANCED')
                }}<Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <label class="mt-3 flex flex-col gap-2">
                <span class="text-label text-n-slate-12">{{
                  t('CRM.AI_SETTINGS.API_BASE')
                }}</span>
                <input v-model="form.apiBase" type="text" :class="fieldCls" />
                <span
                  class="text-label-small leading-relaxed text-n-slate-11"
                  >{{ t('CRM.AI_SETTINGS.API_BASE_HINT') }}</span
                >
              </label>
              <p
                class="mb-0 mt-3 text-label-small leading-relaxed text-n-slate-11"
              >
                {{ t('CRM.AI_SETTINGS.MODEL_HINT') }}
              </p>
            </details>
            <div
              class="mt-5 flex flex-col items-start gap-3 border-t border-n-weak pt-5"
            >
              <Button
                :label="
                  testing
                    ? t('CRM.AI_SETTINGS.TESTING')
                    : t('CRM.AI_SETTINGS.TEST')
                "
                icon="i-lucide-plug-zap"
                variant="faded"
                color="slate"
                :is-disabled="testing || loading"
                @click="testConnection"
              />
              <p
                v-if="testResult"
                role="status"
                class="mb-0 inline-flex items-start gap-2 text-label-small leading-relaxed"
                :class="testResult.ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                <Icon
                  :icon="
                    testResult.ok
                      ? 'i-lucide-check-circle-2'
                      : 'i-lucide-x-circle'
                  "
                  class="mt-0.5 size-4 shrink-0"
                />{{ testResult.message }}
              </p>
            </div>
          </section>

          <section :class="panelCls" aria-labelledby="apollo-heading">
            <div class="mb-3 flex items-center justify-between gap-3">
              <h2 id="apollo-heading" class="text-heading-2 text-n-slate-12">
                {{ copy('APOLLO') }}
              </h2>
              <span
                class="rounded-full bg-n-alpha-2 px-2.5 py-1 text-label-small text-n-slate-11"
                >{{ copy('OPTIONAL') }}</span
              >
            </div>
            <p class="mb-6 text-label-small leading-relaxed text-n-slate-11">
              {{ copy('APOLLO_SUMMARY') }}
            </p>
            <label class="flex flex-col gap-2">
              <span class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-label text-n-slate-12">{{
                  t('CRM.AI_SETTINGS.API_KEY')
                }}</span>
                <span
                  v-if="apolloConfigured"
                  class="inline-flex items-center gap-1 text-label-small text-n-slate-11"
                  ><Icon icon="i-lucide-check-circle-2" class="size-3.5" />{{
                    t('CRM.AI_SETTINGS.KEY_CONFIGURED', { hint: apolloKeyHint })
                  }}</span
                >
              </span>
              <input
                v-model="form.apolloKey"
                type="password"
                autocomplete="off"
                :placeholder="
                  apolloConfigured
                    ? copy('KEY_SET')
                    : t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_NEW')
                "
                :class="fieldCls"
              />
            </label>
            <div
              class="mt-5 grid gap-4 border-t border-n-weak pt-4 sm:grid-cols-2"
            >
              <label class="flex flex-col gap-2">
                <span class="text-label text-n-slate-12">{{
                  copy('APOLLO_MONTHLY_LIMIT')
                }}</span>
                <input
                  v-model.number="form.apolloMonthlyLimit"
                  type="number"
                  min="0"
                  :placeholder="copy('APOLLO_LIMIT_BLANK')"
                  :class="fieldCls"
                />
              </label>
              <label class="flex flex-col gap-2">
                <span class="text-label text-n-slate-12">{{
                  copy('APOLLO_USER_LIMIT')
                }}</span>
                <input
                  v-model.number="form.apolloUserLimit"
                  type="number"
                  min="0"
                  :placeholder="copy('APOLLO_LIMIT_BLANK')"
                  :class="fieldCls"
                />
              </label>
            </div>
            <label class="mt-4 flex flex-col gap-2 border-t border-n-weak pt-4">
              <span class="text-label text-n-slate-12">{{
                copy('LEAD_CRITERIA')
              }}</span>
              <textarea
                v-model="form.leadDefaultCriteria"
                rows="4"
                :placeholder="copy('LEAD_CRITERIA_PLACEHOLDER')"
                :class="fieldCls"
              />
            </label>
            <div
              v-if="aiUsageRows.length"
              class="mt-4 border-t border-n-weak pt-3"
            >
              <div class="mb-2 text-label-small text-n-slate-10">
                {{ copy('AI_USAGE') }}
              </div>
              <div class="grid gap-2 sm:grid-cols-2">
                <div
                  v-for="r in aiUsageRows"
                  :key="r.key"
                  class="flex items-center justify-between rounded-xl border border-n-weak px-3 py-2 text-label-small"
                >
                  <span class="text-n-slate-11">{{ r.label }}</span>
                  <span class="tabular-nums text-n-slate-12">{{
                    copy('AI_USAGE_ROW', {
                      calls: r.calls,
                      tokens: Math.round(r.tokens / 1000),
                    })
                  }}</span>
                </div>
              </div>
            </div>
            <!-- 个别人单独配额：骨干多给、新人少给。留空就跟随上面的「每人上限」。 -->
            <details class="group mt-4 border-t border-n-weak pt-3">
              <summary
                class="flex min-h-10 cursor-pointer list-none items-center justify-between text-label-small text-n-slate-11 [&::-webkit-details-marker]:hidden"
              >
                {{ copy('APOLLO_PER_USER') }}
                <Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <div class="mt-3 grid gap-2 sm:grid-cols-2">
                <label
                  v-for="m in members"
                  :key="m.id"
                  class="flex items-center justify-between gap-2 rounded-xl border border-n-weak px-3 py-2"
                >
                  <span
                    class="min-w-0 truncate text-label-small text-n-slate-12"
                  >
                    {{ m.crm_name || m.name }}
                    <span v-if="usageByUser[m.id]" class="text-n-slate-10">
                      ·
                      {{
                        copy('APOLLO_U_UNLOCK', {
                          n: usageByUser[m.id].unlocked,
                        })
                      }}
                      <template v-if="usageByUser[m.id].contact_fetch">
                        ·
                        {{
                          copy('APOLLO_U_CONTACT', {
                            n: usageByUser[m.id].contact_fetch,
                          })
                        }}
                      </template>
                      <template v-if="usageByUser[m.id].bg_check">
                        ·
                        {{
                          copy('APOLLO_U_BG', { n: usageByUser[m.id].bg_check })
                        }}
                      </template>
                    </span>
                  </span>
                  <input
                    v-model.number="form.apolloUserLimits[String(m.id)]"
                    type="number"
                    min="0"
                    :placeholder="String(form.apolloUserLimit || '')"
                    class="h-8 w-20 shrink-0 rounded-lg border border-n-weak bg-n-alpha-black2 px-2 text-right text-label-small"
                  />
                </label>
              </div>
            </details>
            <p class="mt-3 text-label-small text-n-slate-11">
              {{
                copy('APOLLO_USED', {
                  unlocked: apolloUsage.unlocked_this_month || 0,
                  checks: apolloUsage.bg_checks_this_month || 0,
                })
              }}
            </p>
            <details class="group mt-5 border-t border-n-weak pt-3">
              <summary
                class="flex min-h-10 cursor-pointer list-none items-center justify-between text-label-small text-n-slate-11 [&::-webkit-details-marker]:hidden"
              >
                {{ copy('APOLLO_HELP')
                }}<Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <p
                class="mb-0 mt-2 text-label-small leading-relaxed text-n-slate-11"
              >
                {{ t('CRM.AI_SETTINGS.APOLLO_HINT') }}
              </p>
            </details>
          </section>
        </div>

        <div v-show="activeTab === 'features'" class="space-y-5">
          <section :class="panelCls" aria-labelledby="members-heading">
            <div class="mb-5">
              <h2 id="members-heading" class="text-heading-2 text-n-slate-12">
                {{ copy('MEMBERS') }}
              </h2>
              <p
                class="mb-0 mt-2 text-label-small leading-relaxed text-n-slate-11"
              >
                {{ copy('MEMBERS_NOTE') }}
              </p>
            </div>
            <div
              class="grid max-h-64 grid-cols-1 gap-2 overflow-y-auto sm:grid-cols-2 xl:grid-cols-3"
            >
              <button
                v-for="m in members"
                :key="m.id"
                type="button"
                :aria-pressed="form.agentUserIds.includes(String(m.id))"
                class="flex min-h-11 min-w-0 items-center gap-3 rounded-lg border px-3 py-2 text-left text-label transition-colors"
                :class="
                  form.agentUserIds.includes(String(m.id))
                    ? 'border-n-slate-8 bg-n-alpha-2 text-n-slate-12'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                @click="toggleAgentUser(m.id)"
              >
                <span
                  class="grid size-4 shrink-0 place-items-center rounded border"
                  :class="
                    form.agentUserIds.includes(String(m.id))
                      ? 'border-n-slate-12 bg-n-slate-12 text-n-solid-1'
                      : 'border-n-slate-7'
                  "
                  aria-hidden="true"
                  ><Icon
                    v-if="form.agentUserIds.includes(String(m.id))"
                    icon="i-lucide-check"
                    class="size-3" /></span
                ><span class="truncate">{{ m.name }}</span>
              </button>
              <p
                v-if="!members.length"
                class="mb-0 text-label-small text-n-slate-11"
              >
                {{ copy('NO_MEMBERS') }}
              </p>
            </div>
          </section>

          <section :class="panelCls" aria-labelledby="automation-heading">
            <h2
              id="automation-heading"
              class="mb-5 text-heading-2 text-n-slate-12"
            >
              {{ copy('AUTOMATION') }}
            </h2>
            <div class="flex items-start justify-between gap-6">
              <div class="min-w-0">
                <h3 id="triage-label" class="text-heading-3 text-n-slate-12">
                  {{ copy('TRIAGE') }}
                </h3>
                <p
                  class="mb-0 mt-2 text-label-small leading-relaxed text-n-slate-11"
                >
                  {{ copy('TRIAGE_NOTE') }}
                </p>
              </div>
              <div class="flex h-10 shrink-0 items-center">
                <ToggleSwitch
                  v-model="form.inquiryTriageEnabled"
                  :class="form.inquiryTriageEnabled ? '!bg-[#ffca35]' : ''"
                  aria-labelledby="triage-label"
                />
              </div>
            </div>
            <div class="mt-5 border-t border-n-weak pt-5">
              <div class="flex items-start justify-between gap-6">
                <div class="min-w-0">
                  <h3 id="draft-label" class="text-heading-3 text-n-slate-12">
                    {{ copy('AUTO_DRAFT') }}
                  </h3>
                  <p
                    class="mb-0 mt-2 text-label-small leading-relaxed text-n-slate-11"
                  >
                    {{ copy('AUTO_DRAFT_NOTE') }}
                  </p>
                </div>
                <div class="flex h-10 shrink-0 items-center">
                  <ToggleSwitch
                    v-model="form.autoDraftReplyEnabled"
                    :class="form.autoDraftReplyEnabled ? '!bg-[#ffca35]' : ''"
                    aria-labelledby="draft-label"
                  />
                </div>
              </div>
              <div
                v-if="form.autoDraftReplyEnabled"
                class="mt-5 rounded-xl bg-n-alpha-1 p-4"
              >
                <h3 class="text-heading-3 text-n-slate-12">
                  {{ copy('PILOT') }}
                </h3>
                <p
                  class="mb-4 mt-2 text-label-small leading-relaxed text-n-slate-11"
                >
                  {{ copy('PILOT_NOTE') }}
                </p>
                <div
                  class="grid max-h-48 grid-cols-1 gap-2 overflow-y-auto sm:grid-cols-2 xl:grid-cols-3"
                >
                  <button
                    v-for="m in members"
                    :key="m.id"
                    type="button"
                    :aria-pressed="form.autoDraftUserIds.includes(String(m.id))"
                    class="flex min-h-11 min-w-0 items-center gap-3 rounded-lg border px-3 py-2 text-left text-label transition-colors"
                    :class="
                      form.autoDraftUserIds.includes(String(m.id))
                        ? 'border-n-slate-8 bg-n-alpha-2 text-n-slate-12'
                        : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                    "
                    @click="toggleAutoDraftUser(m.id)"
                  >
                    <span
                      class="grid size-4 shrink-0 place-items-center rounded border"
                      :class="
                        form.autoDraftUserIds.includes(String(m.id))
                          ? 'border-n-slate-12 bg-n-slate-12 text-n-solid-1'
                          : 'border-n-slate-7'
                      "
                      aria-hidden="true"
                      ><Icon
                        v-if="form.autoDraftUserIds.includes(String(m.id))"
                        icon="i-lucide-check"
                        class="size-3" /></span
                    ><span class="truncate">{{ m.name }}</span>
                  </button>
                  <p
                    v-if="!members.length"
                    class="mb-0 text-label-small text-n-slate-11"
                  >
                    {{ copy('NO_MEMBERS') }}
                  </p>
                </div>
              </div>
            </div>
            <details class="group mt-5 border-t border-n-weak pt-3">
              <summary
                class="flex min-h-10 cursor-pointer list-none items-center justify-between text-label-small text-n-slate-11 [&::-webkit-details-marker]:hidden"
              >
                {{ copy('AUTOMATION_HELP')
                }}<Icon
                  icon="i-lucide-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <p
                class="mb-0 mt-2 max-w-3xl text-label-small leading-relaxed text-n-slate-11"
              >
                {{ copy('AUTOMATION_DETAILS') }}
              </p>
            </details>
          </section>
        </div>

        <section
          v-show="activeTab === 'usage'"
          :class="panelCls"
          aria-labelledby="usage-heading"
        >
          <h2 id="usage-heading" class="text-heading-2 text-n-slate-12">
            {{ copy('usage') }}
          </h2>
          <template v-if="usage">
            <dl class="mb-0 mt-6 grid grid-cols-2 gap-6 lg:grid-cols-4">
              <div>
                <dt class="text-label-small text-n-slate-11">
                  {{ copy('ROUNDS') }}
                </dt>
                <dd
                  class="m-0 mt-2 text-heading-1 tabular-nums text-n-slate-12"
                >
                  {{ usage.rounds }}
                </dd>
              </div>
              <div>
                <dt class="text-label-small text-n-slate-11">
                  {{ copy('USERS') }}
                </dt>
                <dd
                  class="m-0 mt-2 text-heading-1 tabular-nums text-n-slate-12"
                >
                  {{ usage.users }}
                </dd>
              </div>
              <div>
                <dt class="text-label-small text-n-slate-11">
                  {{ copy('TIME') }}
                </dt>
                <dd
                  class="m-0 mt-2 text-heading-1 tabular-nums text-n-slate-12"
                >
                  {{ usage.avg_seconds
                  }}<span class="ml-1 text-label-small">{{
                    copy('SECONDS')
                  }}</span>
                </dd>
              </div>
              <div>
                <dt class="text-label-small text-n-slate-11">
                  {{ copy('FAILED') }}
                </dt>
                <dd
                  class="m-0 mt-2 text-heading-1 tabular-nums"
                  :class="
                    usage.failed > 0 ? 'text-n-ruby-11' : 'text-n-slate-12'
                  "
                >
                  {{ usage.failed }}
                </dd>
              </div>
            </dl>
            <div
              class="mt-6 flex flex-wrap gap-x-8 gap-y-3 border-t border-n-weak pt-5 text-label-small text-n-slate-11"
            >
              <span
                >{{ copy('INPUT_TOKENS') }}
                <strong class="ml-2 font-medium tabular-nums text-n-slate-12">{{
                  tokenText(usage.input_tokens)
                }}</strong></span
              ><span
                >{{ copy('OUTPUT_TOKENS') }}
                <strong class="ml-2 font-medium tabular-nums text-n-slate-12">{{
                  tokenText(usage.output_tokens)
                }}</strong></span
              >
            </div>
          </template>
          <p v-else class="mb-0 mt-6 text-label-small text-n-slate-11">
            {{ copy('NO_USAGE') }}
          </p>
          <p
            class="mb-0 mt-6 border-t border-n-weak pt-5 text-label-small leading-relaxed text-n-slate-11"
          >
            {{ copy('BILLING') }}
          </p>
        </section>
      </div>
    </div>
  </CrmSettingsLayout>
</template>
