<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmMemberAPI from 'dashboard/api/crm/members';
import CrmKpiSchemeAPI from 'dashboard/api/crm/kpiSchemes';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const dialogRef = ref(null);
const schemeId = ref(null);
const members = ref([]);
const selected = ref(new Set());
const loading = ref(false);
const busy = ref(false);

// 全员可下发（被考核对象不限 CRM 角色，运营等无角色成员也能选）；默认勾选 CRM 销售/主管。
const roleLabel = m => {
  if (m.crm_role === 'manager') return t('CRM.KPI_SHEETS.ROLE_MANAGER');
  if (m.crm_role === 'sales') return t('CRM.KPI_SHEETS.ROLE_SALES');
  return t('CRM.KPI_SHEETS.ROLE_MEMBER');
};

const open = async id => {
  schemeId.value = id;
  selected.value = new Set();
  loading.value = true;
  dialogRef.value?.open();
  try {
    const { data } = await CrmMemberAPI.get();
    members.value = data.payload || [];
    selected.value = new Set(
      members.value.filter(m => m.crm_role).map(m => m.user_id)
    );
  } catch {
    members.value = [];
  } finally {
    loading.value = false;
  }
};

const toggle = uid => {
  const s = new Set(selected.value);
  if (s.has(uid)) {
    s.delete(uid);
  } else {
    s.add(uid);
  }
  selected.value = s;
};

const count = computed(() => selected.value.size);

const confirm = async () => {
  if (!count.value) return;
  busy.value = true;
  try {
    const { data } = await CrmKpiSchemeAPI.distribute(schemeId.value, [
      ...selected.value,
    ]);
    useAlert(
      t('CRM.KPI_SHEETS.DISTRIBUTE_DONE', {
        created: data.created,
        skipped: data.skipped,
      })
    );
    dialogRef.value?.close();
  } catch {
    useAlert(t('CRM.KPI_SHEETS.DISTRIBUTE_ERROR'));
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="t('CRM.KPI_SHEETS.DISTRIBUTE_TITLE')"
    :confirm-button-label="t('CRM.KPI_SHEETS.DISTRIBUTE_CONFIRM', { count })"
    :is-loading="busy"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-2">
      <p class="text-xs text-n-slate-11">
        {{ t('CRM.KPI_SHEETS.DISTRIBUTE_HINT') }}
      </p>
      <div v-if="loading" class="p-4 text-sm text-center text-n-slate-11">
        {{ t('CRM.KPI_SHEETS.LOADING') }}
      </div>
      <div
        v-else-if="!members.length"
        class="p-4 text-sm text-center text-n-slate-11"
      >
        {{ t('CRM.KPI_SHEETS.NO_SALES') }}
      </div>
      <label
        v-for="m in members"
        :key="m.user_id"
        class="flex items-center gap-3 px-3 py-2 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
      >
        <input
          type="checkbox"
          :checked="selected.has(m.user_id)"
          @change="toggle(m.user_id)"
        />
        <span class="font-medium text-n-slate-12">{{ m.name }}</span>
        <span class="ml-auto text-xs text-n-slate-10">{{ roleLabel(m) }}</span>
      </label>
    </div>
  </Dialog>
</template>
