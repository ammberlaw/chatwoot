<script setup>
import { computed, reactive, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmMemberAPI from 'dashboard/api/crm/members';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const { t } = useI18n();
const dialogRef = ref(null);
const members = ref([]);

const form = reactive({
  name: '',
  ownerId: '',
  monthlySalary: '',
  performanceRatio: '10',
  baselineTarget: '',
  rankNote: '',
});

const isFormInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  form.name = '';
  form.ownerId = '';
  form.monthlySalary = '';
  form.performanceRatio = '10';
  form.baselineTarget = '';
  form.rankNote = '';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const toMicros = v => (v ? Math.round(parseFloat(v) * 1_000_000) : null);

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  emit('create', {
    name: form.name.trim(),
    ownerId: form.ownerId || null,
    monthlySalaryMicros: toMicros(form.monthlySalary),
    performanceRatio: form.performanceRatio ? Number(form.performanceRatio) : null,
    baselineTargetMicros: toMicros(form.baselineTarget),
    rankNote: form.rankNote.trim() || null,
  });
};

onMounted(async () => {
  try {
    const { data } = await CrmMemberAPI.get();
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
});

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('CRM.EMPLOYEE_COMPS.CREATE.TITLE')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('CRM.EMPLOYEE_COMPS.FORM.NAME')"
        autofocus
      />
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('CRM.EMPLOYEE_COMPS.FORM.MEMBER') }}
        <select
          v-model="form.ownerId"
          class="h-10 px-3 rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option value="">—</option>
          <option v-for="m in members" :key="m.user_id" :value="m.user_id">
            {{ m.name }}
          </option>
        </select>
      </label>
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.monthlySalary"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.MONTHLY_SALARY')"
        />
        <Input
          v-model="form.performanceRatio"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.PERF_RATIO')"
        />
      </div>
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.baselineTarget"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.BASELINE_TARGET')"
        />
        <Input
          v-model="form.rankNote"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.RANK_NOTE')"
        />
      </div>
    </div>
  </Dialog>
</template>
