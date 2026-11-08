<script setup>
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmPoolSettingsAPI from 'dashboard/api/crm/publicPoolSettings';
import CrmMemberAPI from 'dashboard/api/crm/members';
import CrmOptionItemsAPI from 'dashboard/api/crm/optionItems';

import Button from 'dashboard/components-next/button/Button.vue';

import HScrollButtons from 'dashboard/components-next/HScrollButtons.vue';
const { t } = useI18n();
const settingsTab = ref('rules');
const settingsTabs = ['rules', 'groups', 'exempt'];
// 与后端 PublicPoolSetting 列一一对应：pool_limit_* 私海上限，recycle_days_* 分组回收天数。
// key 是列名后缀，其大写即客户设置里对应分组的 code；显示名优先取「客户设置→分组设置」的当前名字，
// 取不到再回退到这里的默认名（管理员在客户设置改了分组名，这张表跟着变）。
const GROUPS = [
  { key: 'key_account_won', label: '成交重点客户' },
  { key: 'won', label: '成交客户' },
  { key: 'sample_won', label: '成交样品客户' },
  { key: 'not_won', label: '未成交客户' },
  { key: 'social_media', label: '社媒开发客户' },
];

const form = reactive({
  recycleEnabled: true,
  staleDays: 90,
  recycleNeverFollowed: false,
  limits: Object.fromEntries(GROUPS.map(g => [g.key, ''])),
  recycleDays: Object.fromEntries(GROUPS.map(g => [g.key, ''])),
  exemptUserIds: [],
  claimCooldownDays: 30,
  monthlyReportEnabled: true,
});
const loading = ref(true);
const busy = ref(false);

// 分组显示名：默认取 GROUPS 里的回退名，onMounted 后按 code 用客户设置里的当前名覆盖。
const groupLabels = reactive(
  Object.fromEntries(GROUPS.map(g => [g.key, g.label]))
);

// 回收豁免名单的候选成员（该页仅管理员可见，成员接口返回全员）。
const members = ref([]);
const fetchMembers = async () => {
  try {
    // 只取在职成员：离职停用的人不该再出现在选人下拉里（后端按 deactivated_at 过滤）。
    // 只要 CRM 成员：公海规则管的是客户与商机的归属，车间/仓管/质检从不持有客户，
    // 列进来只会让人在四十来个名字里翻半天。
    const { data } = await CrmMemberAPI.get({ active: true, crm: true });
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
};

// 用「客户设置→分组设置」的当前名字覆盖公海分组名（按 code 匹配，key 大写即 code）。
const fetchGroupNames = async () => {
  try {
    const { data } = await CrmOptionItemsAPI.get('customer_group');
    const byCode = Object.fromEntries(
      (data.payload || []).map(i => [i.code, i.name])
    );
    GROUPS.forEach(g => {
      const name = byCode[g.key.toUpperCase()];
      if (name) groupLabels[g.key] = name;
    });
  } catch {
    // 取不到就用回退名，不阻断
  }
};

onMounted(async () => {
  try {
    const { data } = await CrmPoolSettingsAPI.get();
    form.recycleEnabled = data.recycle_enabled !== false;
    form.staleDays = data.stale_days ?? 90;
    form.recycleNeverFollowed = data.recycle_never_followed === true;
    GROUPS.forEach(g => {
      form.limits[g.key] = data[`pool_limit_${g.key}`] ?? '';
      form.recycleDays[g.key] = data[`recycle_days_${g.key}`] ?? '';
    });
    form.exemptUserIds = data.exempt_user_ids || [];
    form.claimCooldownDays = data.claim_cooldown_days ?? 30;
    form.monthlyReportEnabled = data.monthly_report_enabled !== false;
    fetchMembers();
    fetchGroupNames();
  } catch {
    useAlert(t('CRM.POOL_SETTINGS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
});

// 留空 = 不限/用默认；保存时空串转 null
const toNullable = value =>
  value === '' || value === null ? null : Number(value);

const save = async () => {
  busy.value = true;
  try {
    const setting = {
      recycle_enabled: form.recycleEnabled,
      stale_days: Number(form.staleDays) || 90,
      recycle_never_followed: form.recycleNeverFollowed,
      exempt_user_ids: form.exemptUserIds,
      claim_cooldown_days: Number(form.claimCooldownDays) || 0,
      monthly_report_enabled: form.monthlyReportEnabled,
    };
    GROUPS.forEach(g => {
      setting[`pool_limit_${g.key}`] = toNullable(form.limits[g.key]);
      setting[`recycle_days_${g.key}`] = toNullable(form.recycleDays[g.key]);
    });
    await CrmPoolSettingsAPI.updateSetting({ setting });
    useAlert(t('CRM.POOL_SETTINGS.SAVED'));
  } catch {
    useAlert(t('CRM.POOL_SETTINGS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const fieldCls =
  'h-10 px-3 text-label border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <HScrollButtons />
  <CrmSettingsLayout
    width="narrow"
    :title="t('CRM.SETTINGS_PAGE.POOL')"
    :description="t('CRM.SETTINGS_PAGE.POOL_NOTE')"
  >
    <template #actions
      ><Button
        :label="t('CRM.POOL_SETTINGS.SAVE')"
        icon="i-lucide-check"
        color="iris"
        :is-disabled="busy || loading"
        @click="save"
    /></template>
    <template #toolbar
      ><nav
        class="flex w-fit max-w-full gap-1 overflow-x-auto rounded-xl bg-n-alpha-2 p-1"
        :aria-label="t('CRM.SETTINGS_PAGE.POOL')"
      >
        <button
          v-for="item in settingsTabs"
          :key="item"
          type="button"
          :aria-pressed="settingsTab === item"
          class="min-h-10 shrink-0 rounded-lg px-4 text-label transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-slate-10"
          :class="
            settingsTab === item
              ? 'bg-n-slate-12 text-n-solid-1 shadow-sm'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="settingsTab = item"
        >
          {{ t(`CRM.SETTINGS_PAGE.POOL_${item}`) }}
        </button>
      </nav></template
    >
    <div v-if="loading" class="py-12 text-center text-label text-n-slate-11">
      {{ t('CRM.POOL_SETTINGS.LOADING') }}
    </div>
    <div v-else class="space-y-5">
      <!-- 客户流转规则 -->
      <div
        v-show="settingsTab === 'rules'"
        class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <div class="text-heading-2 text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.RECYCLE_SECTION') }}
          </div>
          <div class="mt-0.5 text-label-small text-n-slate-10">
            {{ t('CRM.POOL_SETTINGS.RECYCLE_HINT') }}
          </div>
        </div>
        <label
          class="flex min-h-11 items-center gap-3 rounded-lg bg-n-alpha-1 px-3 py-2 text-label text-n-slate-12"
        >
          <input v-model="form.recycleEnabled" type="checkbox" />
          {{ t('CRM.POOL_SETTINGS.RECYCLE_ENABLED') }}
        </label>
        <label class="flex flex-col gap-1.5">
          <span class="text-label text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.STALE_DAYS') }}
          </span>
          <span class="text-label-small text-n-slate-10">
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
        <label
          class="flex min-h-11 items-center gap-3 rounded-lg bg-n-alpha-1 px-3 py-2 text-label text-n-slate-12"
        >
          <input
            v-model="form.recycleNeverFollowed"
            type="checkbox"
            :disabled="!form.recycleEnabled"
          />
          {{ t('CRM.POOL_SETTINGS.RECYCLE_NEVER_FOLLOWED') }}
        </label>
        <!-- eslint-disable vue/no-bare-strings-in-template -->
        <label class="flex flex-col gap-1.5">
          <span class="text-label text-n-slate-12">{{
            t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_1')
          }}</span>
          <span class="text-label-small text-n-slate-10">
            {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_2') }}
          </span>
          <input
            v-model="form.claimCooldownDays"
            type="number"
            min="0"
            class="!h-9 !w-32 !max-w-full font-normal"
            :class="[fieldCls]"
          />
        </label>
        <!-- eslint-enable vue/no-bare-strings-in-template -->
      </div>

      <!-- 分组规则：各分组的回收天数 + 私海上限 -->
      <div
        v-show="settingsTab === 'groups'"
        class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <div class="text-heading-2 text-n-slate-12">
            {{ t('CRM.POOL_SETTINGS.GROUP_SECTION') }}
          </div>
          <div class="mt-0.5 text-label-small text-n-slate-10">
            {{ t('CRM.POOL_SETTINGS.GROUP_HINT') }}
          </div>
        </div>
        <!-- 手机卡片：每个分组一张卡 -->
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="row in GROUPS"
            :key="`m-${row.key}`"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
          >
            <div class="text-heading-2 text-n-slate-12">
              {{ groupLabels[row.key] }}
            </div>
            <label class="flex flex-col gap-1 mt-2">
              <span class="text-label-small text-n-slate-11">
                {{ t('CRM.POOL_SETTINGS.COL_DAYS') }}
              </span>
              <input
                v-model="form.recycleDays[row.key]"
                type="number"
                min="1"
                :placeholder="
                  t('CRM.POOL_SETTINGS.USE_DEFAULT', { days: form.staleDays })
                "
                class="w-full"
                :class="[fieldCls]"
              />
            </label>
            <label class="flex flex-col gap-1 mt-2">
              <span class="text-label-small text-n-slate-11">
                {{ t('CRM.POOL_SETTINGS.COL_LIMIT') }}
              </span>
              <input
                v-model="form.limits[row.key]"
                type="number"
                min="0"
                :placeholder="t('CRM.POOL_SETTINGS.NO_LIMIT')"
                class="w-full"
                :class="[fieldCls]"
              />
            </label>
          </div>
        </div>
        <table
          class="hidden w-full table-fixed border-collapse text-label font-normal md:table"
        >
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="w-2/5 py-2 pr-3 font-medium text-left">
                {{ t('CRM.POOL_SETTINGS.COL_GROUP') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('CRM.POOL_SETTINGS.COL_DAYS') }}
              </th>
              <th class="px-3 py-2 font-medium text-left">
                {{ t('CRM.POOL_SETTINGS.COL_LIMIT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in GROUPS"
              :key="row.key"
              class="border-b border-n-weak"
            >
              <td class="py-2 pr-3 font-normal text-n-slate-12">
                {{ groupLabels[row.key] }}
              </td>
              <td class="px-3 py-2">
                <input
                  v-model="form.recycleDays[row.key]"
                  type="number"
                  min="1"
                  :placeholder="
                    t('CRM.POOL_SETTINGS.USE_DEFAULT', { days: form.staleDays })
                  "
                  class="!h-9 !w-32 !max-w-full font-normal"
                  :class="[fieldCls]"
                />
              </td>
              <td class="px-3 py-2">
                <input
                  v-model="form.limits[row.key]"
                  type="number"
                  min="0"
                  :placeholder="t('CRM.POOL_SETTINGS.NO_LIMIT')"
                  class="!h-9 !w-32 !max-w-full font-normal"
                  :class="[fieldCls]"
                />
              </td>
            </tr>
          </tbody>
        </table>
        <p class="text-label-small text-n-slate-10">
          {{ t('CRM.POOL_SETTINGS.GROUP_NOTE') }}
        </p>
      </div>

      <!-- 回收豁免成员：名单内成员的客户与商机不参与自动回收 -->
      <!-- eslint-disable vue/no-bare-strings-in-template -->
      <div
        v-show="settingsTab === 'exempt'"
        class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <div class="text-heading-2 text-n-slate-12">
            {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_3') }}
          </div>
          <div class="mt-0.5 text-label-small text-n-slate-10">
            {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_4') }}
          </div>
        </div>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <label
            v-for="m in members"
            :key="m.user_id"
            class="flex min-h-11 items-center gap-3 rounded-lg bg-n-alpha-1 px-3 py-2 text-label text-n-slate-12"
          >
            <input
              v-model="form.exemptUserIds"
              type="checkbox"
              :value="m.user_id"
            />
            {{ m.name }}
          </label>
        </div>
        <p v-if="!members.length" class="text-label-small text-n-slate-10">
          {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_5') }}
        </p>
      </div>

      <!-- 工作月报：每月 1 号自动给各成员发上月经营数据（按各自权限范围） -->
      <div
        v-show="settingsTab === 'exempt'"
        class="flex flex-col gap-5 rounded-2xl border border-n-weak bg-n-solid-1 p-5 sm:p-6"
      >
        <div>
          <div class="text-heading-2 text-n-slate-12">
            {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_6') }}
          </div>
          <div class="mt-0.5 text-label-small text-n-slate-10">
            {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_7') }}
          </div>
        </div>
        <label
          class="flex min-h-11 items-center gap-3 rounded-lg bg-n-alpha-1 px-3 py-2 text-label text-n-slate-12"
        >
          <input v-model="form.monthlyReportEnabled" type="checkbox" />
          {{ t('CRM.SETTINGS_COPY.PUBLICPOOLSETTINGS_8') }}
        </label>
      </div>
    </div>
  </CrmSettingsLayout>
</template>
