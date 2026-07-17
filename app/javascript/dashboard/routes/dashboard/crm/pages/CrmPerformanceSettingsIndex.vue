<script setup>
import { ref, reactive, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMemberAPI from 'dashboard/api/crm/members';
import CrmPerfSettingsAPI from 'dashboard/api/crm/performanceSettings';

import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const members = ref([]);
const form = reactive({
  hrOwnerId: '',
  gmOwnerId: '',
  schemeVisibleManager: true,
  sheetVisibleSales: true,
  sheetVisibleManager: true,
});
const loading = ref(true);
const busy = ref(false);

onMounted(async () => {
  try {
    const [mem, setting] = await Promise.all([
      CrmMemberAPI.get(),
      CrmPerfSettingsAPI.get(),
    ]);
    members.value = mem.data.payload || [];
    const d = setting.data;
    form.hrOwnerId = d.hr_owner_id || '';
    form.gmOwnerId = d.gm_owner_id || '';
    form.schemeVisibleManager = d.scheme_visible_manager !== false;
    form.sheetVisibleSales = d.sheet_visible_sales !== false;
    form.sheetVisibleManager = d.sheet_visible_manager !== false;
  } catch {
    useAlert(t('CRM.PERF_SETTINGS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
});

const save = async () => {
  busy.value = true;
  try {
    await CrmPerfSettingsAPI.updateSetting({
      setting: {
        hr_owner_id: form.hrOwnerId || null,
        gm_owner_id: form.gmOwnerId || null,
        scheme_visible_manager: form.schemeVisibleManager,
        sheet_visible_sales: form.sheetVisibleSales,
        sheet_visible_manager: form.sheetVisibleManager,
      },
    });
    useAlert(t('CRM.PERF_SETTINGS.SAVED'));
  } catch {
    useAlert(t('CRM.PERF_SETTINGS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const fieldCls = 'h-10 px-3 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12';
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5">
    <div class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak">
      <div>
        <h1 class="text-xl font-medium text-n-slate-12">{{ t('CRM.PERF_SETTINGS.HEADER') }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-11">{{ t('CRM.PERF_SETTINGS.SUBTITLE') }}</p>
      </div>
      <Button :label="t('CRM.PERF_SETTINGS.SAVE')" icon="i-lucide-check" color="iris" :is-disabled="busy || loading" @click="save" />
    </div>
    <div v-if="loading" class="flex items-center justify-center flex-1 text-n-slate-11">{{ t('CRM.PERF_SETTINGS.LOADING') }}</div>
    <div v-else class="flex flex-col w-full max-w-xl gap-5 px-6 py-6">
      <label class="flex flex-col gap-1.5">
        <span class="text-sm text-n-slate-12">{{ t('CRM.PERF_SETTINGS.HR') }}</span>
        <span class="text-xs text-n-slate-10">{{ t('CRM.PERF_SETTINGS.HR_HINT') }}</span>
        <select v-model="form.hrOwnerId" :class="fieldCls">
          <option value="">—</option>
          <option v-for="m in members" :key="m.user_id" :value="m.user_id">{{ m.name }}</option>
        </select>
      </label>
      <label class="flex flex-col gap-1.5">
        <span class="text-sm text-n-slate-12">{{ t('CRM.PERF_SETTINGS.GM') }}</span>
        <span class="text-xs text-n-slate-10">{{ t('CRM.PERF_SETTINGS.GM_HINT') }}</span>
        <select v-model="form.gmOwnerId" :class="fieldCls">
          <option value="">—</option>
          <option v-for="m in members" :key="m.user_id" :value="m.user_id">{{ m.name }}</option>
        </select>
      </label>

      <!-- 板块可见性矩阵 -->
      <div class="flex flex-col gap-3 pt-4 mt-2 border-t border-n-weak">
        <div>
          <div class="text-sm font-medium text-n-slate-12">{{ t('CRM.PERF_SETTINGS.VISIBILITY') }}</div>
          <div class="mt-0.5 text-xs text-n-slate-10">{{ t('CRM.PERF_SETTINGS.VISIBILITY_HINT') }}</div>
        </div>
        <table class="text-sm border-collapse">
          <thead class="text-n-slate-11">
            <tr class="border-b border-n-weak">
              <th class="py-2 pr-4 font-medium text-left" />
              <th class="px-4 py-2 font-medium text-center">{{ t('CRM.PERF_SETTINGS.ROLE_SALES') }}</th>
              <th class="px-4 py-2 font-medium text-center">{{ t('CRM.PERF_SETTINGS.ROLE_MANAGER') }}</th>
              <th class="px-4 py-2 font-medium text-center text-n-slate-10">{{ t('CRM.PERF_SETTINGS.ROLE_ADMIN') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr class="border-b border-n-weak">
              <td class="py-2.5 pr-4 text-n-slate-12">{{ t('CRM.PERF_SETTINGS.ITEM_SCHEME') }}</td>
              <td class="px-4 text-center text-n-slate-10" title="考核方案对业务员/普通成员固定不可见">—</td>
              <td class="px-4 text-center"><input v-model="form.schemeVisibleManager" type="checkbox" /></td>
              <td class="px-4 text-center text-n-slate-10">✓</td>
            </tr>
            <tr class="border-b border-n-weak">
              <td class="py-2.5 pr-4 text-n-slate-12">{{ t('CRM.PERF_SETTINGS.ITEM_SHEET') }}</td>
              <td class="px-4 text-center"><input v-model="form.sheetVisibleSales" type="checkbox" /></td>
              <td class="px-4 text-center"><input v-model="form.sheetVisibleManager" type="checkbox" /></td>
              <td class="px-4 text-center text-n-slate-10">✓</td>
            </tr>
            <tr>
              <td class="py-2.5 pr-4 text-n-slate-11">{{ t('CRM.PERF_SETTINGS.ITEM_COMP') }}</td>
              <td class="px-4 text-center text-n-slate-9">—</td>
              <td class="px-4 text-center text-n-slate-9">—</td>
              <td class="px-4 text-center text-n-slate-10">✓</td>
            </tr>
          </tbody>
        </table>
        <p class="text-xs text-n-slate-10">{{ t('CRM.PERF_SETTINGS.VISIBILITY_NOTE') }}</p>
      </div>
    </div>
  </div>
</template>
