<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({ request: { type: Object, required: true } });
const emit = defineEmits(['updated', 'deleted']);
const { t } = useI18n();
const label = key => t(`CRM.OA_WORKFLOW.${key}`);
const events = ref([]);
const people = ref([]);
const target = ref('');
const reason = ref('');
const transferring = ref(false);
const busy = ref(false);
const error = ref('');
const expanded = ref(false);
let alive = true;
let generation = 0;
const date = value => (value ? new Date(value).toLocaleString() : '');
const loadHistory = async () => {
  generation += 1;
  const current = generation;
  try {
    const { data } = await RequestsAPI.events(props.request.id);
    if (alive && current === generation) events.value = data.payload || [];
  } catch {
    if (alive) error.value = label('FAILED');
  }
};
const run = async operation => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await operation();
    if (!alive) return;
    emit('updated', data);
    transferring.value = false;
    await loadHistory();
  } catch (e) {
    if (alive) error.value = e?.response?.data?.error || label('FAILED');
  } finally {
    if (alive) busy.value = false;
  }
};
const deleteDraft = async () => {
  if (busy.value || !window.confirm(label('DELETE_DRAFT_CONFIRM'))) return;
  busy.value = true;
  try {
    await RequestsAPI.delete(props.request.id);
    if (alive) emit('deleted', props.request.id);
  } catch (e) {
    if (alive) error.value = e?.response?.data?.error || label('FAILED');
  } finally {
    if (alive) busy.value = false;
  }
};
const openTransfer = async () => {
  if (busy.value) return;
  error.value = '';
  try {
    const { data } = await RequestsAPI.transferCandidates(props.request.id);
    if (alive) {
      people.value = data.payload || [];
      transferring.value = true;
    }
  } catch (e) {
    if (alive) error.value = e?.response?.data?.error || label('FAILED');
  }
};
const fieldName = key =>
  (props.request.form_fields || []).find(field => field.key === key)?.label ||
  key;
const changes = event => {
  const before = event.payload?.before?.form_data || {};
  const after = event.payload?.after?.form_data || {};
  return [...new Set([...Object.keys(before), ...Object.keys(after)])]
    .filter(key => before[key] !== after[key])
    .map(key => ({
      name: fieldName(key),
      before: before[key] ?? '—',
      after: after[key] ?? '—',
    }));
};
onMounted(loadHistory);
onBeforeUnmount(() => {
  alive = false;
  generation += 1;
});
</script>

<template>
  <div class="mt-6 space-y-3 border-t border-n-weak pt-4">
    <p v-if="request.legacy_snapshot" class="text-label-small text-n-slate-10">
      {{ label('LEGACY_SNAPSHOT') }}
    </p>
    <p
      v-if="request.source_request_id"
      class="text-label-small text-n-slate-10"
    >
      {{ t('CRM.OA_WORKFLOW.SOURCE', { id: request.source_request_id }) }}
    </p>
    <p
      v-if="request.integration_result?.notice"
      class="rounded-lg bg-n-amber-3 p-2 text-label-small text-n-amber-11"
    >
      {{ request.integration_result.notice }}
    </p>
    <p
      v-if="request.waiting_since"
      class="text-label-small"
      :class="request.overdue ? 'text-n-amber-11' : 'text-n-slate-10'"
    >
      {{ label(request.overdue ? 'OVERDUE' : 'WAITING') }} ·
      {{ date(request.waiting_since)
      }}<span v-if="request.waiting_estimated">
        · {{ label('ESTIMATED') }}</span
      >
    </p>
    <p
      v-if="request.cc_readers?.length"
      class="text-label-small text-n-slate-10"
    >
      {{ label('CC_READ')
      }}{{ request.cc_readers.map(reader => reader.name).join('、') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <Button
        v-if="request.status === 'draft' && request.is_applicant"
        :label="label('DELETE_DRAFT')"
        size="sm"
        color="ruby"
        variant="outline"
        :disabled="busy"
        @click="deleteDraft"
      />
      <Button
        v-if="
          request.status === 'pending' &&
          (request.is_applicant || request.can_transfer)
        "
        :label="label('REMIND')"
        icon="i-lucide-bell"
        size="sm"
        color="slate"
        variant="outline"
        :disabled="busy"
        @click="run(() => RequestsAPI.remind(request.id))"
      />
      <Button
        v-if="request.can_transfer"
        :label="label('TRANSFER')"
        icon="i-lucide-user-round-cog"
        size="sm"
        color="slate"
        variant="outline"
        :disabled="busy"
        @click="openTransfer"
      />
      <Button
        :label="label('HISTORY')"
        icon="i-lucide-history"
        size="sm"
        color="slate"
        variant="ghost"
        @click="expanded = !expanded"
      />
    </div>
    <div
      v-if="transferring"
      class="space-y-2 rounded-xl border border-n-weak p-3"
    >
      <label :for="`oa-transfer-${request.id}`" class="block text-label">{{
        label('TRANSFER_TO')
      }}</label>
      <select
        :id="`oa-transfer-${request.id}`"
        v-model="target"
        :disabled="busy"
        class="h-9 w-full rounded-xl border border-n-weak bg-n-solid-1 px-2 text-label-small"
      >
        <option value="">{{ label('CHOOSE_MEMBER') }}</option>
        <option v-for="person in people" :key="person.id" :value="person.id">
          {{ person.name }}
        </option>
      </select>
      <TextArea
        :id="`oa-transfer-reason-${request.id}`"
        v-model="reason"
        :label="label('TRANSFER_REASON')"
        :placeholder="label('TRANSFER_REASON')"
        :disabled="busy"
      />
      <Button
        :label="label('CONFIRM_TRANSFER')"
        size="sm"
        :disabled="busy || !target || !reason.trim()"
        @click="run(() => RequestsAPI.transfer(request.id, target, reason))"
      />
    </div>
    <div v-if="expanded" class="max-h-96 space-y-3 overflow-y-auto">
      <p v-if="!events.length" class="text-label-small text-n-slate-10">
        {{ label('NO_HISTORY') }}
      </p>
      <div
        v-for="event in events"
        :key="event.id"
        class="rounded-lg bg-n-alpha-1 p-3 text-label-small"
      >
        <p class="font-medium">
          {{ label(`EVENT_${event.kind.toUpperCase()}`) }} ·
          {{ event.actor_name || label('SYSTEM') }}
        </p>
        <p class="text-n-slate-10">{{ date(event.created_at) }}</p>
        <p v-if="event.payload?.comment">{{ event.payload.comment }}</p>
        <p v-if="event.payload?.reason">{{ event.payload.reason }}</p>
        <p v-if="event.payload?.from_id">
          {{
            t('CRM.OA_WORKFLOW.TRANSFER_DETAIL', {
              from: event.payload.from_name || event.payload.from_id,
              to: event.payload.to_name || event.payload.to_id,
            })
          }}
        </p>
        <p v-for="change in changes(event)" :key="change.name">
          {{
            t('CRM.OA_WORKFLOW.FIELD_CHANGE', {
              name: change.name,
              before: change.before,
              after: change.after,
            })
          }}
        </p>
        <p
          v-if="
            event.payload?.before?.department_id !==
            event.payload?.after?.department_id
          "
        >
          {{
            t('CRM.OA_WORKFLOW.DEPARTMENT_CHANGE', {
              before:
                event.payload.before?.department_name ||
                event.payload.before?.department_id ||
                '—',
              after:
                event.payload.after?.department_name ||
                event.payload.after?.department_id ||
                '—',
            })
          }}
        </p>
        <a
          v-for="(file, index) in event.files"
          :key="index"
          :href="file.url"
          target="_blank"
          rel="noopener noreferrer"
          class="block truncate text-n-blue-11"
          >{{ label('PREVIOUS_ATTACHMENT') }}{{ file.filename }}</a
        >
        <p v-if="event.payload?.removed_files?.length">
          {{
            t('CRM.OA_WORKFLOW.REMOVED_ATTACHMENTS', {
              files: event.payload.removed_files.join('、'),
            })
          }}
        </p>
        <p v-if="event.payload?.files">
          {{
            t('CRM.OA_WORKFLOW.CURRENT_ATTACHMENTS', {
              files: event.payload.files.join('、') || '—',
            })
          }}
        </p>
      </div>
    </div>
    <p v-if="error" role="alert" class="text-label-small text-n-ruby-11">
      {{ error }}
    </p>
  </div>
</template>
