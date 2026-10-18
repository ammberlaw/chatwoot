<script setup>
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
  // 谁能用 CRM 的 AI 助手（管理员/副管恒可用，不必列进来）
  agentUserIds: [],
  // 陌生来信自动背调+建档+起草回复（会自动花模型调用，默认关）
  inquiryTriageEnabled: false,
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
    form.model = data.model || 'deepseek-chat';
    form.apiBase = data.api_base || 'https://api.deepseek.com/v1';
    form.agentUserIds = (data.agent_user_ids || []).map(String);
    form.inquiryTriageEnabled = !!data.inquiry_triage_enabled;
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
        agent_user_ids: form.agentUserIds.map(Number),
        inquiry_triage_enabled: form.inquiryTriageEnabled,
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
  'h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand';
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3 [.theme-classic_&]:items-center [.theme-classic_&]:sm:!px-8"
    >
      <div class="min-w-0">
        <h1
          class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8"
        >
          {{ t('CRM.AI_SETTINGS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.AI_SETTINGS.SUBTITLE') }}
        </p>
      </div>
      <Button
        class="shrink-0"
        :label="t('CRM.AI_SETTINGS.SAVE')"
        icon="i-lucide-check"
        color="iris"
        :is-disabled="busy || loading"
        @click="save"
      />
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-n-slate-11"
    >
      {{ t('CRM.AI_SETTINGS.LOADING') }}
    </div>

    <div
      v-else
      class="flex flex-col w-full max-w-xl gap-6 px-4 py-4 sm:px-6 sm:py-6 [.theme-classic_&]:sm:!px-8"
    >
      <!-- 供应商 -->
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.AI_SETTINGS.PROVIDER') }}
        </span>
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.AI_SETTINGS.PROVIDER_HINT') }}
        </span>
        <SelectCard
          :model-value="activeProvider"
          :options="providerOptions"
          trigger-class="w-full sm:w-56"
          @update:model-value="applyProvider"
        />
      </label>

      <!-- API Key -->
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.AI_SETTINGS.API_KEY') }}
        </span>
        <span
          v-if="configured"
          class="inline-flex items-center gap-1.5 text-xs text-n-teal-11"
        >
          <Icon icon="i-lucide-check-circle-2" class="size-3.5" />
          {{ t('CRM.AI_SETTINGS.KEY_CONFIGURED', { hint: keyHint }) }}
        </span>
        <input
          v-model="form.apiKey"
          type="password"
          autocomplete="off"
          :placeholder="
            configured
              ? t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_SET')
              : t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_NEW')
          "
          :class="[fieldCls]"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.AI_SETTINGS.KEY_HINT') }}
        </span>
      </label>

      <!-- 模型 -->
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.AI_SETTINGS.MODEL') }}
        </span>
        <input
          v-model="form.model"
          type="text"
          class="w-full sm:w-56"
          :class="[fieldCls]"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.AI_SETTINGS.MODEL_HINT') }}
        </span>
      </label>

      <!-- 端点 -->
      <label class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.AI_SETTINGS.API_BASE') }}
        </span>
        <input v-model="form.apiBase" type="text" :class="[fieldCls]" />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.AI_SETTINGS.API_BASE_HINT') }}
        </span>
      </label>

      <!-- Apollo 企业库（客户背调按域名补全公司概况 + 联系人） -->
      <label class="flex flex-col gap-1.5 pt-4 border-t border-n-weak">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.AI_SETTINGS.APOLLO_KEY') }}
        </span>
        <span
          v-if="apolloConfigured"
          class="inline-flex items-center gap-1.5 text-xs text-n-teal-11"
        >
          <Icon icon="i-lucide-check-circle-2" class="size-3.5" />
          {{ t('CRM.AI_SETTINGS.KEY_CONFIGURED', { hint: apolloKeyHint }) }}
        </span>
        <input
          v-model="form.apolloKey"
          type="password"
          autocomplete="off"
          :placeholder="
            apolloConfigured
              ? t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_SET')
              : t('CRM.AI_SETTINGS.KEY_PLACEHOLDER_NEW')
          "
          :class="[fieldCls]"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.AI_SETTINGS.APOLLO_HINT') }}
        </span>
      </label>

      <!-- AI 助手使用名单：勾谁谁能用（管理员/副管恒可用，不必勾） -->
      <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <span class="text-label text-n-slate-12">AI 助手开放给谁</span>
        <span class="text-xs text-n-slate-10">
          勾中的人能用 CRM 右下角的 AI 助手。管理员和副管理员一直可用，不用勾。
          它只能查到这个人本来就有权限看的客户和邮件。
        </span>
        <div
          class="flex flex-wrap gap-1.5 p-2 border rounded-lg border-n-weak max-h-40 overflow-y-auto"
        >
          <button
            v-for="m in members"
            :key="m.id"
            type="button"
            class="px-2.5 py-1 text-xs rounded-full reset-base"
            :class="
              form.agentUserIds.includes(String(m.id))
                ? 'bg-n-iris-9 text-white'
                : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="toggleAgentUser(m.id)"
          >
            {{ m.name }}
          </button>
          <span v-if="!members.length" class="text-xs text-n-slate-10">
            没有可选成员。
          </span>
        </div>
      </div>

      <!-- 本月用量：只读。有数才谈得上「该不该给谁开」「要不要换模型」 -->
      <div
        v-if="usage"
        class="flex flex-wrap items-center gap-x-6 gap-y-2 px-3 py-2.5 border rounded-lg border-n-weak bg-n-alpha-1"
      >
        <span class="text-label text-n-slate-12">本月用量</span>
        <span class="text-xs text-n-slate-11">
          问答 {{ usage.rounds }} 轮 · {{ usage.users }} 人用过
        </span>
        <span class="text-xs text-n-slate-11">
          token 进 {{ tokenText(usage.input_tokens) }} / 出
          {{ tokenText(usage.output_tokens) }}
        </span>
        <span class="text-xs text-n-slate-11">
          平均 {{ usage.avg_seconds }} 秒/轮
        </span>
        <span
          class="text-xs"
          :class="usage.failed > 0 ? 'text-n-ruby-11' : 'text-n-slate-11'"
        >
          失败 {{ usage.failed }} 轮
        </span>
      </div>

      <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <div class="flex items-center gap-3">
          <ToggleSwitch v-model="form.inquiryTriageEnabled" />
          <span class="text-label text-n-slate-12">新询盘自动初筛</span>
        </div>
        <span class="text-xs text-n-slate-10">
          收到陌生人来信时自动背调这家公司、查系统里有没有人已经在跟；判断是真实公司才建客户档案并起草一封回复草稿，
          结果发到「团队沟通」。草稿不会自动发出。开着会自动消耗模型调用，默认关。
        </span>
      </div>

      <!-- 测试连接 -->
      <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <div class="flex flex-wrap items-center gap-3">
          <Button
            :label="
              testing ? t('CRM.AI_SETTINGS.TESTING') : t('CRM.AI_SETTINGS.TEST')
            "
            icon="i-lucide-plug-zap"
            variant="faded"
            color="teal"
            :is-disabled="testing || loading"
            @click="testConnection"
          />
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.AI_SETTINGS.TEST_HINT') }}
          </span>
        </div>
        <div
          v-if="testResult"
          class="inline-flex items-center gap-1.5 text-sm"
          :class="testResult.ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          <Icon
            :icon="
              testResult.ok ? 'i-lucide-check-circle-2' : 'i-lucide-x-circle'
            "
            class="size-4"
          />
          {{ testResult.message }}
        </div>
      </div>

      <!-- 计费提示 -->
      <p class="text-xs leading-relaxed text-n-slate-10">
        {{ t('CRM.AI_SETTINGS.BILLING_NOTE') }}
      </p>
    </div>
  </div>
</template>
