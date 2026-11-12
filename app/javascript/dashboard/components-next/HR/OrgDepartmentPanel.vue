<script setup>
import { useI18n } from 'vue-i18n';
const props = defineProps({
  department: { type: Object, required: true },
  members: { type: Array, default: () => [] },
  loading: Boolean,
});
const emit = defineEmits(['close', 'maintain']);
const { t } = useI18n();
const label = key => t(`CRM.HR_WORKFLOW.${key}`);
</script>

<template>
  <aside
    class="w-full shrink-0 overflow-y-auto border-t border-n-weak bg-n-solid-1 p-4 md:w-80 md:border-l md:border-t-0"
  >
    <div class="mb-4 flex items-center justify-between gap-2">
      <h2 class="text-heading-2">{{ department.name }}</h2>
      <button
        :aria-label="label('CLOSE')"
        class="rounded-lg p-2 text-label"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4" aria-hidden="true" />
      </button>
    </div>
    <p class="mb-4 text-label-small">
      {{
        t('CRM.HR_WORKFLOW.LEADER_LABEL', {
          name:
            department.leaderName ||
            label(department.leaderInactive ? 'LEADER_HANDOVER' : 'NOT_SET'),
        })
      }}
    </p>
    <h3 class="mb-3 text-heading-3">
      {{ label('DEPT_MEMBERS') }} · {{ members.length }}
    </h3>
    <p v-if="loading" class="text-label-small" role="status">
      {{ label('LOADING') }}
    </p>
    <ul v-else class="space-y-3">
      <li
        v-for="member in props.members"
        :key="member.id"
        class="rounded-xl border border-n-weak p-3"
      >
        <p class="text-label">{{ member.user_name }}</p>
        <p class="mt-1 text-label-small text-n-slate-10">
          {{ member.title || '—' }} ·
          {{ label(member.is_primary ? 'PRIMARY' : 'SECONDARY') }}
        </p>
      </li>
    </ul>
    <button
      class="mt-4 rounded-xl border border-n-weak px-3 py-2 text-label-small"
      @click="emit('maintain', department.id)"
    >
      {{ label('MAINTAIN_DEPARTMENT') }}
    </button>
  </aside>
</template>
