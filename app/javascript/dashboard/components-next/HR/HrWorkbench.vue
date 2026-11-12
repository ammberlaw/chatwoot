<script setup>
/* global axios */
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  active: Boolean,
  refreshKey: { type: Number, default: 0 },
});
const emit = defineEmits(['open', 'retry']);
const { t } = useI18n();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
const { accountId } = useAccount();
const data = ref({});
const selected = ref('probation');
const error = ref('');
const loading = ref(false);
const tabs = [
  ['probation', 'PROBATION'],
  ['contracts', 'CONTRACT'],
  ['handovers', 'HANDOVER'],
  ['incomplete', 'INCOMPLETE'],
];
let generation = 0;
const load = async () => {
  generation += 1;
  const request = generation;
  data.value = {};
  if (!props.active) return;
  loading.value = true;
  error.value = '';
  try {
    const response = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/employees/workbench`
    );
    if (request === generation) data.value = response.data;
  } catch (failure) {
    if (request === generation)
      error.value = failure?.response?.data?.error || label('FAILED');
  } finally {
    if (request === generation) loading.value = false;
  }
};
watch(() => [props.active, props.refreshKey], load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    v-if="active"
    class="rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h2 class="mb-3 text-heading-3">{{ label('WORKBENCH') }}</h2>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="[key, text] in tabs"
        :key="key"
        class="rounded-lg px-3 py-2 text-label-small"
        :class="
          selected === key
            ? 'bg-n-slate-12 text-n-solid-1'
            : 'bg-n-alpha-1 text-n-slate-11'
        "
        :aria-pressed="selected === key"
        @click="selected = key"
      >
        {{ label(text) }} · {{ data[key]?.length || 0 }}
      </button>
    </div>
    <p v-if="loading" role="status" class="mt-3 text-label-small">
      {{ label('LOADING') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="mt-3 text-label-small text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-else-if="!data[selected]?.length"
      class="mt-3 text-label-small text-n-slate-10"
    >
      {{ label('NO_TASKS') }}
    </p>
    <div v-else class="mt-3 max-h-64 divide-y divide-n-weak overflow-y-auto">
      <div
        v-for="row in data[selected]"
        :key="row.run_id || row.id"
        class="flex flex-wrap items-center justify-between gap-2 py-2"
      >
        <div class="min-w-0 text-label-small">
          <p class="truncate font-medium">
            {{ row.employee_no }} {{ row.name }} · {{ row.department_name }}
          </p>
          <p v-if="row.due_on" class="text-n-slate-10">
            {{ t('CRM.HR_WORKFLOW.DUE_ON', { date: row.due_on }) }}
          </p>
          <p v-if="row.missing" class="text-n-slate-10">
            {{
              t('CRM.HR_WORKFLOW.MISSING_FIELDS', {
                fields: row.missing.join('、'),
              })
            }}
          </p>
          <p v-if="row.error" class="text-n-ruby-11">{{ row.error }}</p>
        </div>
        <Button
          v-if="row.id && row.kind === 'handover' && data.can_offboard"
          :label="label('RETRY_HANDOVER')"
          size="sm"
          variant="outline"
          @click="emit('retry', row)"
        />
        <Button
          v-if="row.id"
          :label="label('OPEN_EMPLOYEE')"
          size="sm"
          variant="outline"
          color="slate"
          @click="emit('open', row)"
        />
      </div>
    </div>
  </section>
</template>
