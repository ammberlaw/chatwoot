<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAiSettingsAPI from 'dashboard/api/crm/aiSettings';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

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
});
const configured = ref(false);
const keyHint = ref(null);
const apolloConfigured = ref(false);
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
      class="flex items-center justify-between flex-shrink-0 gap-3 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12">
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
      class="flex flex-col w-full max-w-xl gap-6 px-4 py-4 sm:px-6 sm:py-6"
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
