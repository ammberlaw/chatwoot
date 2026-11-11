<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import camelcaseKeys from 'camelcase-keys';
import KnowledgeDocsAPI from 'dashboard/api/crm/knowledgeDocs';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  doc: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['updated', 'locate']);
const { t } = useI18n();
const label = key => t(`CRM.KNOWLEDGE_WORKFLOW.${key}`);
const versions = ref([]);
const people = ref([]);
const owner = ref(props.doc.ownerId || '');
const busy = ref(false);
const error = ref('');
const note = ref('');
const replacing = ref('');
const replacementInput = ref(null);
const showVersions = ref(false);
const loadingVersions = ref(false);
const confirmingVersion = ref(null);
let alive = true;
let versionRequest = 0;
const date = value =>
  value ? new Date(value).toLocaleString() : label('HISTORY_UNKNOWN');
const action = async operation => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await operation();
    if (!alive) return;
    if (data?.id) emit('updated', camelcaseKeys(data, { deep: true }));
  } catch (e) {
    if (alive) error.value = e?.response?.data?.error || label('ACTION_ERROR');
  } finally {
    if (alive) busy.value = false;
  }
};
const favorite = () =>
  action(async () => {
    const { data } = await KnowledgeDocsAPI.preference(
      props.doc.id,
      !props.doc.favorite
    );
    if (alive) emit('updated', { ...props.doc, favorite: data.favorite });
    return { data: null };
  });
const loadVersions = async () => {
  showVersions.value = !showVersions.value;
  if (!showVersions.value) return;
  versionRequest += 1;
  const request = versionRequest;
  loadingVersions.value = true;
  error.value = '';
  try {
    const { data } = await KnowledgeDocsAPI.versions(props.doc.id);
    if (alive && request === versionRequest)
      versions.value = data.payload || [];
  } catch {
    if (alive && request === versionRequest)
      error.value = label('ACTION_ERROR');
  } finally {
    if (alive && request === versionRequest) loadingVersions.value = false;
  }
};
const restore = async version => {
  if (confirmingVersion.value !== version.id) {
    confirmingVersion.value = version.id;
    return;
  }
  await action(() => KnowledgeDocsAPI.restoreVersion(props.doc.id, version.id));
  confirmingVersion.value = null;
  showVersions.value = false;
};
const selectReplacement = () => replacementInput.value?.click();
const replace = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file || !replacing.value) return;
  const data = new FormData();
  data.append('file', file);
  data.append('attachment_id', replacing.value);
  data.append('note', note.value);
  await action(() => KnowledgeDocsAPI.replaceFile(props.doc.id, data));
  showVersions.value = false;
};
const saveOwner = () =>
  action(() =>
    KnowledgeDocsAPI.update(props.doc.id, { doc: { owner_id: owner.value } })
  );
onMounted(async () => {
  if (!props.canManage || props.doc.scope === 'PERSONAL') return;
  try {
    const { data } = await KnowledgeDocsAPI.maintainers(props.doc.id);
    if (alive) people.value = data.payload || [];
  } catch {
    if (alive) error.value = label('ACTION_ERROR');
  }
});
onBeforeUnmount(() => {
  alive = false;
  versionRequest += 1;
});
</script>

<template>
  <div class="space-y-3 rounded-xl border border-n-weak p-3">
    <div class="flex flex-wrap items-center gap-2">
      <Button
        :label="label(doc.favorite ? 'UNFAVORITE' : 'FAVORITE')"
        icon="i-lucide-star"
        size="sm"
        color="slate"
        variant="outline"
        :disabled="busy"
        @click="favorite"
      />
      <Button
        :label="label('LOCATE')"
        icon="i-lucide-folder-open"
        size="sm"
        color="slate"
        variant="ghost"
        @click="emit('locate')"
      />
    </div>
    <dl class="grid grid-cols-2 gap-2 text-label-small">
      <dt class="text-n-slate-10">{{ label('UPLOADER') }}</dt>
      <dd>{{ doc.createdByName || label('HISTORY_UNKNOWN') }}</dd>
      <dt class="text-n-slate-10">{{ label('CREATED_AT') }}</dt>
      <dd>{{ date(doc.createdAt) }}</dd>
      <dt class="text-n-slate-10">{{ label('UPDATED_BY') }}</dt>
      <dd>{{ doc.updatedByName || label('HISTORY_UNKNOWN') }}</dd>
      <dt class="text-n-slate-10">{{ label('UPDATED_AT') }}</dt>
      <dd>{{ date(doc.updatedAt) }}</dd>
      <dt class="text-n-slate-10">{{ label('MAINTAINER') }}</dt>
      <dd>{{ doc.ownerName || label('HISTORY_UNKNOWN') }}</dd>
      <dt class="text-n-slate-10">{{ label('PATH') }}</dt>
      <dd class="break-words">{{ doc.folderPath || label('ROOT') }}</dd>
      <dt class="text-n-slate-10">{{ label('EXTRACTION') }}</dt>
      <dd>
        {{ label(`EXTRACT_${(doc.extractState || 'unknown').toUpperCase()}`) }}
      </dd>
    </dl>
    <Button
      v-if="doc.extractState === 'pending'"
      :label="label('REFRESH')"
      size="sm"
      color="slate"
      variant="ghost"
      :disabled="busy"
      @click="action(() => KnowledgeDocsAPI.show(doc.id))"
    />
    <p v-if="doc.extractError" class="text-label-small text-n-ruby-11">
      {{ doc.extractError }}
    </p>
    <div v-if="canManage" class="flex flex-wrap items-center gap-2">
      <Button
        v-if="doc.files?.length"
        :label="label('RETRY_EXTRACTION')"
        size="sm"
        color="slate"
        variant="ghost"
        :disabled="busy || doc.extractState === 'pending'"
        @click="action(() => KnowledgeDocsAPI.retryExtraction(doc.id))"
      />
      <template v-if="doc.scope === 'COMPANY' && people.length">
        <label :for="`maintainer-${doc.id}`" class="text-label-small">{{
          label('MAINTAINER')
        }}</label>
        <select
          :id="`maintainer-${doc.id}`"
          v-model="owner"
          :disabled="busy"
          class="h-9 max-w-40 rounded-xl border border-n-weak bg-n-solid-1 px-2 text-label-small"
        >
          <option v-for="person in people" :key="person.id" :value="person.id">
            {{ person.name }}
          </option>
        </select>
        <Button
          :label="label('SAVE')"
          size="sm"
          color="slate"
          variant="outline"
          :disabled="busy || Number(owner) === doc.ownerId"
          @click="saveOwner"
        />
      </template>
    </div>
    <div
      v-if="canManage && doc.files?.length"
      class="space-y-2 border-t border-n-weak pt-3"
    >
      <label class="block text-label" :for="`replace-file-${doc.id}`">{{
        label('REPLACE_FILE')
      }}</label>
      <select
        :id="`replace-file-${doc.id}`"
        v-model="replacing"
        :disabled="busy"
        class="h-9 w-full rounded-xl border border-n-weak bg-n-solid-1 px-2 text-label-small"
      >
        <option value="">{{ label('CHOOSE_ATTACHMENT') }}</option>
        <option v-for="file in doc.files" :key="file.id" :value="file.id">
          {{ file.filename }}
        </option>
      </select>
      <Input
        v-model="note"
        :placeholder="label('VERSION_NOTE')"
        :aria-label="label('VERSION_NOTE')"
      />
      <Button
        :label="label('REPLACE_FILE')"
        size="sm"
        color="slate"
        variant="outline"
        :disabled="busy || !replacing"
        @click="selectReplacement"
      />
      <input
        ref="replacementInput"
        type="file"
        class="hidden"
        @change="replace"
      />
    </div>
    <Button
      :label="label('VERSIONS')"
      icon="i-lucide-history"
      size="sm"
      color="slate"
      variant="outline"
      :disabled="busy"
      @click="loadVersions"
    />
    <div v-if="showVersions" class="max-h-80 space-y-3 overflow-y-auto">
      <p v-if="loadingVersions" class="text-label-small text-n-slate-10">
        {{ label('LOADING') }}
      </p>
      <p v-else-if="!versions.length" class="text-label-small text-n-slate-10">
        {{ label('NO_VERSIONS') }}
      </p>
      <div
        v-for="version in versions"
        :key="version.id"
        class="space-y-1 rounded-lg bg-n-alpha-1 p-2 text-label-small"
      >
        <p class="font-medium">
          {{
            t('CRM.KNOWLEDGE_WORKFLOW.VERSION_LABEL', {
              number: version.number,
              note: version.note,
            })
          }}
        </p>
        <p class="text-n-slate-10">
          {{ version.user_name || label('HISTORY_UNKNOWN') }} ·
          {{ date(version.created_at) }}
        </p>
        <p>{{ version.name }}</p>
        <p
          v-if="version.summary || version.body"
          class="whitespace-pre-wrap line-clamp-4"
        >
          {{ version.summary }} {{ version.body }}
        </p>
        <a
          v-for="file in version.files"
          :key="file.id"
          :href="file.url"
          target="_blank"
          rel="noopener noreferrer"
          class="block truncate text-n-blue-11"
          >{{ file.filename }}</a
        >
        <Button
          v-if="canManage && version.number !== doc.versionNumber"
          :label="
            label(
              confirmingVersion === version.id
                ? 'CONFIRM_RESTORE'
                : 'RESTORE_VERSION'
            )
          "
          size="sm"
          color="slate"
          variant="ghost"
          :disabled="busy"
          @click="restore(version)"
        />
      </div>
    </div>
    <p v-if="error" role="alert" class="text-label-small text-n-ruby-11">
      {{ error }}
    </p>
  </div>
</template>
