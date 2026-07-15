<script setup>
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmPoolSettingsAPI from 'dashboard/api/crm/publicPoolSettings';

import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const form = reactive({
  recycleEnabled: true,
  staleDays: 90,
  recycleNeverFollowed: false,
  poolLimitKeyAccountWon: '',
  poolLimitWon: '',
  poolLimitSampleWon: '',
  poolLimitNotWon: '',
  poolLimitSocialMedia: '',
});
const loading = ref(true);
const busy = ref(false);

// 分组上限行（顺序与客户分组下拉一致）
const GROUP_ROWS = [
  { key: 'poolLimitKeyAccountWon', label: '大客户（成交）' },
  { key: 'poolLimitWon', label: '已成交' },
  { key: 'poolLimitSampleWon', label: '样品成交' },
  { key: 'poolLimitNotWon', label: '未成交' },
  { key: 'poolLimitSocialMedia', label: '社媒客户' },
];

onMounted(async () => {
  try {
    const { data } = await CrmPoolSettingsAPI.get();
    form.recycleEnabled = data.recycle_enabled !== false;
    form.staleDays = data.stale_days ?? 90;
    form.recycleNeverFollowed = data.recycle_never_followed === true;
    form.poolLimitKeyAccountWon = data.pool_limit_key_account_won ?? '';
    form.poolLimitWon = data.pool_limit_won ?? '';
    form.poolLimitSampleWon = data.pool_limit_sample_won ?? '';
    form.poolLimitNotWon = data.pool_limit_not_won ?? '';
    form.poolLimitSocialMedia = data.pool_limit_social_media ?? '';
  } catch {
    useAlert(t('CRM.POOL_SETTINGS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
});

// 上限留空 = 不限；保存时空串转 null
const toLimit = value =>
  value === '' || value === null ? null : Number(value);

const save = async () => {
  busy.value = true;
  try {
    await CrmPoolSettingsAPI.updateSetting({
      setting: {
        recycle_enabled: form.recycleEnabled,
        stale_days: Number(form.staleDays) || 90,
        recycle_never_followed: form.recycleNeverFollowed,
        pool_limit_key_account_won: toLimit(form.poolLimitKeyAccountWon),
        pool_limit_won: toLimit(form.poolLimitWon),
        pool_limit_sample_won: toLimit(form.poolLimitSampleWon),
        pool_limit_not_won: toLimit(form.poolLimitNotWon),
        pool_limit_social_media: toLimit(form.poolLimitSocialMedia),
      },
    });
    useAlert(t('CRM.POOL_SETTINGS.SAVED'));
  } catch {
    useAlert(t('CRM.POOL_SETTINGS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const fieldCls =
  'h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('CRM.POOL_SETTINGS.HEADER') }}
        </h1>
        <p class="mt-0.5 text-xs text-n-slate-11">
          {{ t('CRM.POOL_SETTINGS.SUBTITLE') }}
        </p>
      </div>
      <Button
        :label="t('CRM.POOL_SETTINGS.SAVE')"
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
      {{ t('CRM.POOL_SETTINGS.LOADING') }}
    </div>
    <div v-else class="flex flex-col w-full max-w-xl gap-5 px-6 py-6">
      <!-- 客户流转规则 -->
      <div class="flex flex-col gap-3">
        <div>
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.RECYCLE_SECTION') }}
          </div>
          <div class="mt-0.5 text-xs text-n-slate-10">
            {{ t('CRM.POOL_SETTINGS.RECYCLE_HINT') }}
          </div>
        </div>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="form.recycleEnabled" type="checkbox" />
          {{ t('CRM.POOL_SETTINGS.RECYCLE_ENABLED') }}
        </label>
        <label class="flex flex-col gap-1.5">
          <span class="text-sm text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.STALE_DAYS') }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ t('CRM.POOL_SETTINGS.STALE_DAYS_HINT') }}
          </span>
          <input
            v-model="form.staleDays"
            type="number"
            min="1"
            :disabled="!form.recycleEnabled"
            class="w-32 disabled:opacity-50"
            :class="[fieldCls]"
          />
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            v-model="form.recycleNeverFollowed"
            type="checkbox"
            :disabled="!form.recycleEnabled"
          />
          {{ t('CRM.POOL_SETTINGS.RECYCLE_NEVER_FOLLOWED') }}
        </label>
      </div>

      <!-- 分组私海上限 -->
      <div class="flex flex-col gap-3 pt-4 mt-2 border-t border-n-weak">
        <div>
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.LIMIT_SECTION') }}
          </div>
          <div class="mt-0.5 text-xs text-n-slate-10">
            {{ t('CRM.POOL_SETTINGS.LIMIT_HINT') }}
          </div>
        </div>
        <table class="text-sm border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="py-2 pr-4 font-medium text-left">
                {{ t('CRM.POOL_SETTINGS.COL_GROUP') }}
              </th>
              <th class="px-4 py-2 font-medium text-left">
                {{ t('CRM.POOL_SETTINGS.COL_LIMIT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in GROUP_ROWS"
              :key="row.key"
              class="border-b border-n-weak"
            >
              <td class="py-2.5 pr-4 text-n-slate-12">{{ row.label }}</td>
              <td class="px-4 py-1.5">
                <input
                  v-model="form[row.key]"
                  type="number"
                  min="0"
                  :placeholder="t('CRM.POOL_SETTINGS.NO_LIMIT')"
                  class="w-32"
                  :class="[fieldCls]"
                />
              </td>
            </tr>
          </tbody>
        </table>
        <p class="text-xs text-n-slate-10">
          {{ t('CRM.POOL_SETTINGS.LIMIT_NOTE') }}
        </p>
      </div>
    </div>
  </div>
</template>
