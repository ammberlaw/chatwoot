<script setup>
// 业务分配设置：管理各收件箱（如 WhatsApp）的协作者——即会话「分配业务」下拉可选的人。
// 原生「设置→收件箱→协作者」页要 administrator 权限（副管进不去），这里放 CRM 设置组，超管+副管可用。
import { ref, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import InboxCollaboratorsAPI from 'dashboard/api/crm/inboxCollaborators';
import Button from 'dashboard/components-next/button/Button.vue';

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
  <div
    class="flex flex-col w-full h-full overflow-auto bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div class="flex-shrink-0 px-4 py-3 border-b border-n-weak sm:px-6 sm:py-4 [.theme-classic_&]:sm:!px-8">
      <h1 class="text-xl font-medium text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">业务分配设置</h1>
      <p class="mt-0.5 text-xs text-n-slate-11">
        选中的成员才会出现在会话右键「分配业务」下拉里，可被分配处理该收件箱的对话。
      </p>
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      加载中…
    </div>

    <div v-else class="flex flex-col gap-4 p-4 sm:p-6 [.theme-classic_&]:sm:!p-8">
      <div
        v-for="ib in inboxes"
        :key="ib.id"
        class="p-4 border shadow-sm rounded-2xl border-white/60 bg-n-solid-1/60"
      >
        <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
          <div class="flex items-center gap-2">
            <span class="text-sm font-semibold text-n-slate-12">{{
              ib.name
            }}</span>
            <span
              class="px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ channelLabel(ib.channel_type) }}
            </span>
            <span class="text-xs text-n-slate-10">
              已选 {{ (selected[ib.id] || []).length }} 人
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="text-xs text-n-slate-11 hover:text-n-slate-12"
              @click="selectAll(ib.id)"
            >
              全选
            </button>
            <span class="text-n-slate-6">·</span>
            <button
              type="button"
              class="text-xs text-n-slate-11 hover:text-n-slate-12"
              @click="clearAll(ib.id)"
            >
              清空
            </button>
            <Button
              label="保存"
              icon="i-lucide-check"
              color="iris"
              size="sm"
              :is-loading="savingId === ib.id"
              @click="save(ib.id)"
            />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-3 lg:grid-cols-4">
          <label
            v-for="c in candidates"
            :key="c.id"
            class="flex items-center gap-2 px-2.5 py-2 text-sm border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
            :class="
              isChecked(ib.id, c.id)
                ? 'bg-n-iris-3 border-n-iris-6'
                : 'bg-n-solid-1/40'
            "
          >
            <input
              type="checkbox"
              class="accent-n-iris-9"
              :checked="isChecked(ib.id, c.id)"
              @change="toggle(ib.id, c.id)"
            />
            <span class="truncate text-n-slate-12">{{ c.name }}</span>
            <span
              v-if="ROLE_LABEL[c.crm_role]"
              class="ml-auto shrink-0 text-[11px] text-n-slate-10"
            >
              {{ ROLE_LABEL[c.crm_role] }}
            </span>
          </label>
        </div>
      </div>

      <p v-if="!inboxes.length" class="text-sm text-n-slate-10">
        还没有收件箱。
      </p>
    </div>
  </div>
</template>
