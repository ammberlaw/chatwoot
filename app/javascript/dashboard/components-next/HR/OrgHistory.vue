<script setup>
/* global axios */
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
const props = defineProps({ departmentId: { type: Number, default: null } });
const { accountId } = useAccount();
const { t } = useI18n();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
const expanded = ref(false);
const rows = ref([]);
const error = ref('');
const loading = ref(false);
let generation = 0;
const load = async () => {
  generation += 1;
  const request = generation;
  rows.value = [];
  if (!expanded.value) return;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/org/departments/history`,
      { params: { department_id: props.departmentId } }
    );
    if (request === generation) rows.value = data.payload || [];
  } catch (failure) {
    if (request === generation)
      error.value = failure?.response?.data?.error || label('FAILED');
  } finally {
    if (request === generation) loading.value = false;
  }
};
watch(() => [expanded.value, props.departmentId], load);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section class="border-t border-n-weak p-4">
    <button
      class="text-label"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      {{ label('ORG_HISTORY') }}
    </button>
    <div v-if="expanded" class="mt-3 max-h-64 space-y-3 overflow-y-auto">
      <p v-if="loading" role="status" class="text-label-small">
        {{ label('LOADING') }}
      </p>
      <p v-else-if="error" role="alert" class="text-label-small text-n-ruby-11">
        {{ error }}
      </p>
      <p v-else-if="!rows.length" class="text-label-small text-n-slate-10">
        {{ label('NO_HISTORY') }}
      </p>
      <article
        v-for="row in rows"
        :key="row.id"
        class="rounded-lg bg-n-alpha-1 p-3 text-label-small"
      >
        <p>
          {{ label(row.kind.toUpperCase()) }} · {{ row.actor_name }} ·
          {{ new Date(row.created_at).toLocaleString() }}
        </p>
        <p>
          {{ row.payload.department_name }} {{ row.payload.user_name }}
          {{ row.payload.title }}
        </p>
        <p v-for="(values, field) in row.payload.changes || {}" :key="field">
          {{
            t('CRM.HR_WORKFLOW.CHANGE_FIELD', {
              field: label(
                field === 'name'
                  ? 'DEPARTMENT'
                  : field === 'leader_id'
                    ? 'LEADER'
                    : field === 'archived_at'
                      ? 'STOPPED_DEPARTMENT'
                      : 'PARENT_DEPARTMENT'
              ),
              before: values[0] || '—',
              after: values[1] || '—',
            })
          }}
        </p>
      </article>
    </div>
  </section>
</template>
