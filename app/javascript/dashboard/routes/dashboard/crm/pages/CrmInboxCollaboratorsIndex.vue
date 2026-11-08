<script setup>
import { useI18n } from 'vue-i18n';
import CrmSettingsLayout from 'dashboard/components-next/CRM/CrmSettingsLayout.vue';
// 业务分配设置：管理各收件箱（如 WhatsApp）的协作者——即会话「分配业务」下拉可选的人。
// 原生「设置→收件箱→协作者」页要 administrator 权限（副管进不去），这里放 CRM 设置组，超管+副管可用。
import { ref, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import InboxCollaboratorsAPI from 'dashboard/api/crm/inboxCollaborators';
import Button from 'dashboard/components-next/button/Button.vue';

const { t: translate } = useI18n();
const loading = ref(true);
const savingId = ref(null);
const inboxes = ref([]);
const candidates = ref([]);
// 每个收件箱当前勾选的成员 id 集合（数组，便于响应式）。
const selected = reactive({});

const ROLE_LABEL = {
  administrator: '管理员',
  deputy_admin: '副管理员',
  manager: '部门主管',
  sales: '业务员',
  hr: '人事',
};

const CHANNEL_LABEL = {
  'Channel::Whatsapp': 'WhatsApp',
  'Channel::WhatsappWeb': 'WhatsApp',
  'Channel::Email': '邮件',
  'Channel::WebWidget': '网页',
  'Channel::Api': 'API',
};
const channelLabel = t => CHANNEL_LABEL[t] || t;

const load = async () => {
  loading.value = true;
  try {
    const { data } = await InboxCollaboratorsAPI.get();
    inboxes.value = data.inboxes || [];
    candidates.value = data.candidates || [];
    inboxes.value.forEach(ib => {
      selected[ib.id] = [...(ib.member_ids || [])];
    });
  } catch {
    useAlert('加载失败，请刷新重试');
  } finally {
    loading.value = false;
  }
};

const isChecked = (inboxId, uid) => (selected[inboxId] || []).includes(uid);
const toggle = (inboxId, uid) => {
  const list = selected[inboxId] || [];
  selected[inboxId] = list.includes(uid)
    ? list.filter(x => x !== uid)
    : [...list, uid];
};
const selectAll = inboxId => {
  selected[inboxId] = candidates.value.map(c => c.id);
};
const clearAll = inboxId => {
  selected[inboxId] = [];
};

const save = async inboxId => {
  savingId.value = inboxId;
  try {
    const { data } = await InboxCollaboratorsAPI.save(
      inboxId,
      selected[inboxId]
    );
    selected[inboxId] = [...(data.member_ids || [])];
    useAlert('已保存，会话「分配业务」将显示这些人');
  } catch (e) {
    useAlert(e.response?.data?.error || '保存失败，请重试');
  } finally {
    savingId.value = null;
  }
};

onMounted(load);
</script>

<template>
  <CrmSettingsLayout
    :title="translate('CRM.SETTINGS_PAGE.INBOX')"
    :description="translate('CRM.SETTINGS_PAGE.INBOX_NOTE')"
  >
    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-label text-n-slate-11"
    >
      {{ translate('CRM.SETTINGS_COPY.INBOXCOLLABORATORS_1') }}
    </div>

    <div v-else class="space-y-4">
      <details
        v-for="(ib, index) in inboxes"
        :key="ib.id"
        :open="index === 0"
        class="group rounded-2xl border border-n-weak bg-n-solid-1"
      >
        <summary
          class="flex min-h-16 cursor-pointer list-none items-center gap-3 p-5 [&::-webkit-details-marker]:hidden"
        >
          <span
            class="i-lucide-inbox size-5 shrink-0 text-n-slate-11"
            aria-hidden="true"
          />
          <span
            class="min-w-0 flex-1 truncate text-heading-2 text-n-slate-12"
            >{{ ib.name }}</span
          >
          <span class="hidden text-label-small text-n-slate-11 sm:inline">{{
            channelLabel(ib.channel_type)
          }}</span>
          <span
            class="shrink-0 rounded-full bg-n-alpha-2 px-2.5 py-1 text-label-small text-n-slate-11"
            >{{
              translate('CRM.SETTINGS_PAGE.PICKED', {
                count: (selected[ib.id] || []).length,
              })
            }}</span
          >
          <span
            class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-11 transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </summary>
        <div class="border-t border-n-weak p-5 sm:p-6">
          <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
            <span class="text-label text-n-slate-12">{{
              translate('CRM.SETTINGS_PAGE.COLLABORATORS')
            }}</span>
            <div class="flex items-center gap-2">
              <button
                type="button"
                class="min-h-10 px-2 text-label-small text-n-slate-11 hover:text-n-slate-12"
                @click="selectAll(ib.id)"
              >
                {{ translate('CRM.SETTINGS_COPY.INBOXCOLLABORATORS_2') }}
              </button>
              <span class="text-n-slate-6">·</span>
              <button
                type="button"
                class="min-h-10 px-2 text-label-small text-n-slate-11 hover:text-n-slate-12"
                @click="clearAll(ib.id)"
              >
                {{ translate('CRM.SETTINGS_COPY.INBOXCOLLABORATORS_3') }}
              </button>
              <Button
                :label="translate('CRM.SETTINGS_COPY.INBOXCOLLABORATORS_4')"
                icon="i-lucide-check"
                color="iris"
                size="sm"
                :is-loading="savingId === ib.id"
                @click="save(ib.id)"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <label
              v-for="c in candidates"
              :key="c.id"
              class="flex items-center gap-2 min-h-12 px-3 py-3 text-label border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
              :class="
                isChecked(ib.id, c.id)
                  ? 'bg-n-alpha-2 border-n-slate-7'
                  : 'bg-n-solid-1/40'
              "
            >
              <input
                type="checkbox"
                class="size-4 shrink-0 accent-n-slate-12"
                :checked="isChecked(ib.id, c.id)"
                @change="toggle(ib.id, c.id)"
              />
              <span class="truncate text-n-slate-12">{{ c.name }}</span>
              <span
                v-if="ROLE_LABEL[c.crm_role]"
                class="ml-auto shrink-0 text-label-small text-n-slate-10"
              >
                {{ ROLE_LABEL[c.crm_role] }}
              </span>
            </label>
          </div>
        </div>
      </details>

      <p v-if="!inboxes.length" class="text-label text-n-slate-10">
        {{ translate('CRM.SETTINGS_COPY.INBOXCOLLABORATORS_5') }}
      </p>
    </div>
  </CrmSettingsLayout>
</template>
